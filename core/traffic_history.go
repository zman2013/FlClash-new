package main

import (
	"core/internal/traffichistory"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var proxyTrafficHistory atomic.Pointer[traffichistory.Store]
var trafficHistoryWorker sync.Once
var trafficHistoryLocation atomic.Pointer[time.Location]

func trafficHistoryNow() time.Time {
	now := time.Now()
	if loc := trafficHistoryLocation.Load(); loc != nil {
		return now.In(loc)
	}
	return now
}

func initTrafficHistory(home string) {
	if runtime.GOOS != "android" || proxyTrafficHistory.Load() != nil {
		return
	}
	// Go uses UTC for time.Local on Android; use the phone's calendar timezone.
	if zone, err := exec.Command("/system/bin/getprop", "persist.sys.timezone").Output(); err == nil {
		if loc, err := time.LoadLocation(strings.TrimSpace(string(zone))); err == nil {
			trafficHistoryLocation.Store(loc)
		}
	}
	store, err := traffichistory.Open(home, trafficHistoryNow())
	if err != nil {
		log.Errorln("Proxy traffic history: %s", err)
	}
	proxyTrafficHistory.Store(store)
	trafficHistoryWorker.Do(func() {
		go func() {
			ticker := time.NewTicker(time.Second)
			defer ticker.Stop()
			for range ticker.C {
				flushTrafficHistory()
			}
		}()
	})
}

func flushTrafficHistory() {
	if store := proxyTrafficHistory.Load(); store != nil {
		_ = store.Flush()
	}
}

func init() {
	if runtime.GOOS != "android" {
		return
	}
	statistic.DefaultTrafficNotify = func(info *statistic.TrackerInfo, up, down int64) {
		store := proxyTrafficHistory.Load()
		if store == nil {
			return
		}
		app := strings.TrimSpace(info.Metadata.Process)
		if app == "" && info.Metadata.ProcessPath != "" {
			app = filepath.Base(info.Metadata.ProcessPath)
		}
		store.Add(trafficHistoryNow(), app, info.Chain, up, down)
	}
}
