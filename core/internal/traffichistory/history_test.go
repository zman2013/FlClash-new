package traffichistory

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestBackgroundDeltasImportRestartAndRetention(t *testing.T) {
	home := t.TempDir()
	now := time.Date(2026, 11, 10, 23, 59, 59, 0, time.FixedZone("CST", 8*3600))
	_ = os.WriteFile(filepath.Join(home, "weekly-traffic.json"), []byte(`{"2026-11-10":{"Legacy":100},"2026-11-03":{"Expired":999}}`), 0600)
	s, err := Open(home, now)
	if err != nil {
		t.Fatal(err)
	}
	// No snapshots, polling, UI events, or event listener are needed.
	s.Add(now, "app.a", []string{"Node", "Proxy"}, 10, 20)
	s.Add(now, "app.a", []string{"DIRECT"}, 900, 900)
	s.Add(now, "app.a", []string{"REJECT-DROP"}, 900, 900)
	s.Add(now, "app.a", nil, 900, 900)
	s.Add(now.Add(2*time.Second), "app.a", []string{"Node"}, 1, 2)
	if err := s.Flush(); err != nil {
		t.Fatal(err)
	}
	next, err := Open(home, now.Add(3*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	got := next.Snapshot(now.Add(3 * time.Second))
	if got.Days["2026-11-10"]["app.a"] != 30 || got.Days["2026-11-11"]["app.a"] != 3 || got.Days["2026-11-10"]["Legacy"] != 100 {
		t.Fatalf("wrong daily totals after restart: %#v", got)
	}
	if _, ok := got.Days["2026-11-03"]; ok {
		t.Fatal("expired data retained")
	}
	if !got.CompleteSince.Equal(now) {
		t.Fatal("migration boundary was reset")
	}
	if err := next.Flush(); err != nil {
		t.Fatal(err)
	}
	again, err := Open(home, now.Add(3*time.Second))
	if err != nil || again.Snapshot(now.Add(3 * time.Second)).Days["2026-11-10"]["Legacy"] != 100 {
		t.Fatal("duplicate import", err)
	}
}

func TestConcurrentDeltasAndSaves(t *testing.T) {
	home := t.TempDir()
	now := time.Now()
	s, _ := Open(home, now)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				s.Add(now, "app", []string{"Node"}, 3, 7)
				if j%20 == 0 {
					if err := s.Flush(); err != nil {
						t.Error(err)
					}
				}
			}
		}()
	}
	wg.Wait()
	if err := s.Flush(); err != nil {
		t.Fatal(err)
	}
	restored, err := Open(home, now)
	if err != nil {
		t.Fatal(err)
	}
	if got := restored.Snapshot(now).Days[now.Format("2006-01-02")]["app"]; got != 8000 {
		t.Fatal("lost or duplicated bytes", got)
	}
	snap := restored.Snapshot(now)
	snap.Days[now.Format("2006-01-02")]["app"] = 0
	if restored.Snapshot(now).Days[now.Format("2006-01-02")]["app"] != 8000 {
		t.Fatal("mutable snapshot")
	}
}

func TestCorruptHistoryIsReportedAndNotOverwritten(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, "proxy-traffic-history.json")
	_ = os.WriteFile(path, []byte("{broken"), 0600)
	s, err := Open(home, time.Now())
	if err == nil || s.Snapshot(time.Now()).Error == "" {
		t.Fatal("read error hidden")
	}
	s.Add(time.Now(), "app", []string{"Node"}, 1, 2)
	if s.Flush() == nil {
		t.Fatal("overwrote corrupt history")
	}
	b, _ := os.ReadFile(path)
	if string(b) != "{broken" {
		t.Fatal("history destroyed")
	}
}

func TestNullLegacyDoesNotPanicOrOverwrite(t *testing.T) {
	home := t.TempDir()
	_ = os.WriteFile(filepath.Join(home, "weekly-traffic.json"), []byte("null"), 0600)
	s, err := Open(home, time.Now())
	if err == nil {
		t.Fatal("invalid legacy data accepted")
	}
	s.Add(time.Now(), "app", []string{"Node"}, 1, 2)
	if s.Flush() == nil {
		t.Fatal("read failure hidden")
	}
}

func TestSaveErrorClearsAfterRetryAndRestart(t *testing.T) {
	home := t.TempDir()
	now := time.Now()
	s, _ := Open(home, now)
	s.Add(now, "app", []string{"Node"}, 1, 2)
	tmp := filepath.Join(home, "proxy-traffic-history.json.tmp")
	if err := os.Mkdir(tmp, 0700); err != nil {
		t.Fatal(err)
	}
	if s.Flush() == nil || s.Snapshot(now).Error == "" {
		t.Fatal("write failure hidden")
	}
	if err := os.Remove(tmp); err != nil {
		t.Fatal(err)
	}
	if err := s.Flush(); err != nil {
		t.Fatal(err)
	}
	reopened, err := Open(home, now)
	if err != nil || reopened.Snapshot(now).Error != "" {
		t.Fatal("stale write error persisted", err)
	}
}
