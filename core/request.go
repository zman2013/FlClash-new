package main

import (
	"time"

	"github.com/metacubex/mihomo/common/utils"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type RequestInfo struct {
	ID          string      `json:"id"`
	Upload      int64       `json:"upload"`
	Download    int64       `json:"download"`
	Start       time.Time   `json:"start"`
	Metadata    *C.Metadata `json:"metadata"`
	Chains      []string    `json:"chains"`
	Rule        string      `json:"rule"`
	RulePayload string      `json:"rulePayload"`
	Success     bool        `json:"success"`
	Error       string      `json:"error"`
}

func requestInfoFromTracker(tracker statistic.Tracker) *RequestInfo {
	info := tracker.Info()
	return &RequestInfo{
		ID:          info.UUID.String(),
		Upload:      info.UploadTotal.Load(),
		Download:    info.DownloadTotal.Load(),
		Start:       info.Start,
		Metadata:    info.Metadata,
		Chains:      append([]string{}, info.Chain...),
		Rule:        info.Rule,
		RulePayload: info.RulePayload,
		Success:     true,
		Error:       "",
	}
}

func requestInfoFromFailure(metadata *C.Metadata, rule C.Rule, proxy C.ProxyAdapter, err error) *RequestInfo {
	chains := []string{}
	if proxy != nil {
		chains = append(chains, proxy.Name())
	}
	ruleName := ""
	rulePayload := ""
	if rule != nil {
		ruleName = rule.RuleType().String()
		rulePayload = rule.Payload()
	}
	errorText := "request failed"
	if err != nil {
		errorText = err.Error()
	}
	return &RequestInfo{
		ID:          utils.NewUUIDV4().String(),
		Upload:      0,
		Download:    0,
		Start:       time.Now(),
		Metadata:    metadata,
		Chains:      chains,
		Rule:        ruleName,
		RulePayload: rulePayload,
		Success:     false,
		Error:       errorText,
	}
}
