// Package traffichistory stores seven calendar days of proxied payload traffic.
// It does not depend on Flutter, connection polling, or connection lifetimes.
package traffichistory

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Snapshot struct {
	Version       int                         `json:"version"`
	CompleteSince time.Time                   `json:"completeSince"`
	Days          map[string]map[string]int64 `json:"days"`
	Error         string                      `json:"error,omitempty"`
}

type Store struct {
	mu        sync.Mutex
	saveMu    sync.Mutex
	path      string
	data      Snapshot
	revision  uint64
	saved     uint64
	readError error
}

// Open imports the old sampled aggregates once. It cannot recover payload that
// the old collector never observed. CompleteSince makes that boundary explicit.
func Open(home string, now time.Time) (*Store, error) {
	s := &Store{path: filepath.Join(home, "proxy-traffic-history.json"),
		data: Snapshot{Version: 1, CompleteSince: now, Days: map[string]map[string]int64{}}}
	b, err := os.ReadFile(s.path)
	if err == nil {
		err = json.Unmarshal(b, &s.data)
		if err == nil && (s.data.Version != 1 || s.data.Days == nil || s.data.CompleteSince.IsZero()) {
			err = errors.New("invalid proxy traffic history")
		}
	} else if errors.Is(err, os.ErrNotExist) {
		b, err = os.ReadFile(filepath.Join(home, "weekly-traffic.json"))
		if err == nil {
			err = json.Unmarshal(b, &s.data.Days)
			if err == nil && s.data.Days == nil {
				err = errors.New("invalid legacy proxy traffic history")
			}
		}
		if errors.Is(err, os.ErrNotExist) {
			err = nil
		}
		s.revision++
	}
	if err != nil {
		// Keep the existing file intact instead of overwriting unreadable history.
		s.readError = err
		s.data.Error = err.Error()
		if s.data.Days == nil {
			s.data.Days = map[string]map[string]int64{}
		}
		return s, err
	}
	s.data.Error = ""
	s.pruneLocked(now)
	return s, nil
}

func proxied(chains []string) bool {
	seen := false
	for _, chain := range chains {
		chain = strings.ToUpper(strings.TrimSpace(chain))
		if chain == "" {
			continue
		}
		seen = true
		if chain == "DIRECT" || strings.HasPrefix(chain, "REJECT") {
			return false
		}
	}
	return seen
}

func (s *Store) Add(now time.Time, app string, chains []string, up, down int64) {
	if up < 0 || down < 0 || up+down <= 0 || !proxied(chains) {
		return
	}
	if app == "" {
		app = "Unknown App"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(now)
	key := now.Format("2006-01-02")
	if s.data.Days[key] == nil {
		s.data.Days[key] = map[string]int64{}
	}
	s.data.Days[key][app] += up + down
	s.revision++
}

func (s *Store) pruneLocked(now time.Time) {
	today := now.Format("2006-01-02")
	first := now.AddDate(0, 0, -6).Format("2006-01-02")
	for date := range s.data.Days {
		if date < first || date > today {
			delete(s.data.Days, date)
			s.revision++
		}
	}
}

func (s *Store) Snapshot(now time.Time) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(now)
	result := s.data
	result.Days = make(map[string]map[string]int64, len(s.data.Days))
	for day, apps := range s.data.Days {
		result.Days[day] = make(map[string]int64, len(apps))
		for app, bytes := range apps {
			result.Days[day][app] = bytes
		}
	}
	return result
}

// Flush serializes atomic replacements. Concurrent Add calls remain dirty for
// the next flush; an older snapshot can never replace a newer saved snapshot.
func (s *Store) Flush() error {
	s.saveMu.Lock()
	defer s.saveMu.Unlock()
	s.mu.Lock()
	if s.readError != nil {
		err := s.readError
		s.mu.Unlock()
		return err
	}
	if s.saved == s.revision {
		s.mu.Unlock()
		return nil
	}
	revision := s.revision
	persisted := s.data
	persisted.Error = "" // Transient I/O errors belong to this session only.
	b, err := json.Marshal(persisted)
	s.mu.Unlock()
	if err == nil {
		temporary := s.path + ".tmp"
		var file *os.File
		file, err = os.OpenFile(temporary, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
		if err == nil {
			_, err = file.Write(b)
			if err == nil {
				err = file.Sync()
			}
			closeErr := file.Close()
			if err == nil {
				err = closeErr
			}
		}
		if err == nil {
			err = os.Rename(temporary, s.path)
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err != nil {
		s.data.Error = err.Error()
	} else {
		s.saved = revision
		s.data.Error = ""
	}
	return err
}
