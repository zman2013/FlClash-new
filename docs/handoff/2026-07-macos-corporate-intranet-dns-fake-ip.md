# Task Title

macOS FlClash 开启 TUN 后公司内网 DNS 与 Fake-IP 排障

## Task Description

在不关闭 FlClash 代理能力的前提下，让 Safari、命令行以及其他应用正确解析并访问公司内网域名；本案例目标域名为 `gerrit.it.chehejia.com`，最终应解析到公司内网地址并完成 HTTPS 访问。

## Preconditions / Trigger

- 平台：macOS，FlClash 开启系统代理、TUN 和 DNS 劫持。
- 公司网络通过 DHCP 下发内网 DNS，例如 `10.122.8.16`、`10.122.8.17`。
- 系统代理绕过列表已经包含 `*chehejia.com` / `*chj.cloud`，但浏览器仍无法打开公司内网。
- DNS 返回 `198.18.0.0/16` 地址，或 TLS 握手立即失败。
- 适用于“Chrome 失败且 Safari 也失败”的全局 DNS/TUN 故障；如果只有访问控制列表中的单一应用失败，还要单独检查 `PROCESS-PATH-REGEX` 规则。

## Solving Steps

1. 确认 FlClash、系统代理、TUN 和 DNS 当前状态：

   ```bash
   pgrep -afil 'FlClash|FlClashCore'
   scutil --proxy
   networksetup -getdnsservers Wi-Fi
   scutil --dns | sed -n '1,80p'
   ```

2. 检查目标域名解析结果；`198.18.x.x` 是 Clash Fake-IP，不是公司内网真实地址：

   ```bash
   dscacheutil -q host -a name gerrit.it.chehejia.com
   dig gerrit.it.chehejia.com A
   route -n get 198.18.0.1
   ```

3. 检查运行时配置和流量日志，判断请求是否仍被 TUN 接管或错误发送到代理节点：

   ```bash
   rg -n -C 4 'fake-ip-filter|nameserver-policy|chehejia|chj\.cloud' \
     "$HOME/Library/Application Support/com.follow.clash/config.yaml"

   rg -n 'gerrit\.it\.chehejia\.com' \
     "$HOME/Library/Application Support/com.follow.clash/traffic_analysis.jsonl" | tail
   ```

4. 从 DHCP 获取公司 DNS，而不是猜测 DNS 地址：

   ```bash
   ipconfig getpacket en0 | \
     rg -i 'yiaddr|router|domain_name_server|domain_name'
   ```

5. 强制查询绑定物理网卡，证明公司 DNS 和目标记录本身正常：

   ```bash
   dig -b "$(ipconfig getifaddr en0)" \
     @10.122.8.16 gerrit.it.chehejia.com A
   ```

   本案例的真实结果为：

   ```text
   gerrit.it.chehejia.com. A 10.132.59.191
   ```

6. 在 FlClash 的「工具 → 高级配置 → DNS → Fakeip过滤」中配置：

   ```text
   +.chehejia.com
   +.chj.cloud
   gerrit.it.chehejia.com
   ```

   `+.example.com` 可匹配任意层级子域名；`*.example.com` 只消耗一个域名标签，不能可靠覆盖 `gerrit.it.chehejia.com` 这类多级域名。

7. 在「工具 → 高级配置 → DNS → Nameserver策略」中配置公司 DNS，并绑定物理网卡：

   ```text
   +.chehejia.com → 10.122.8.16#en0,10.122.8.17#en0
   +.chj.cloud    → 10.122.8.16#en0,10.122.8.17#en0
   ```

   `#en0` 是关键：它避免公司 DNS 上游请求再次进入 `utun`，确保数据包走公司网络物理接口。

8. 确保公司策略排在泛化策略之前。Nameserver 策略按顺序首次命中；如果 `geosite:cn → https://doh.pub/dns-query` 位于公司规则之前，`chehejia.com` 会先命中公网 DNS并返回 `NXDOMAIN`。本案例直接删除了冗余的 `geosite:cn` 策略。

9. 需要重载核心时停下来，请用户手动重启 FlClash；自动化代理不得自行关闭、杀死、启动或重启 FlClash。

10. 重启后验证持久配置、DNS、TLS 和目标页面：

    ```bash
    defaults read com.follow.clash flutter.config | \
      jq '.patchClashConfig.dns | {fakeIpFilter: .["fake-ip-filter"], nameserverPolicy: .["nameserver-policy"]}'

    dig gerrit.it.chehejia.com A

    curl --noproxy '*' -sSI \
      --connect-timeout 8 --max-time 20 \
      'https://gerrit.it.chehejia.com/q/project:cu/compiler/schumacher-toolchain+branch:tmp/neo' \
      -o /dev/null \
      -w 'http_code=%{http_code} remote_ip=%{remote_ip} ssl_verify=%{ssl_verify_result} time_total=%{time_total}\n'
    ```

    本案例最终验证结果：

    ```text
    DNS: gerrit.it.chehejia.com → 10.132.59.191
    HTTPS: http_code=200
    remote_ip=10.132.59.191
    ssl_verify=0
    server=openresty/1.25.3.2
    x-gerrit-instance=gerrit-master-2
    ```

## Tools

- `scutil` / `networksetup`: 检查 macOS 系统代理、绕过列表和实际 DNS 配置。
- `ipconfig getpacket en0`: 读取公司 DHCP 下发的 DNS、网关和搜索域。
- `dig`: 区分 Fake-IP、公网 `NXDOMAIN` 和真实公司内网记录；`-b <en0 IP>` 用于验证物理网卡路径。
- `route -n get`: 判断 DNS 或目标 IP 当前经过 `en0` 还是 `utun`。
- `curl --noproxy '*'`: 绕开 shell 环境代理，验证 DNS、TCP、TLS 和 HTTP 完整链路。
- `traffic_analysis.jsonl`: 通过 `processPath`、`rule`、`chains`、`remoteDestination` 判断请求是否错误命中代理节点。
- FlClash DNS 设置页面：必须通过应用自身 UI 保存持久设置，避免外部修改 plist 后被应用内存旧值覆盖。

## Failure & Recovery

- Symptom: 系统代理绕过列表已有 `*chehejia.com`，但 Safari 和 Chrome 都打不开内网。
  Cause: 系统代理例外只绕过 HTTP/SOCKS 代理，TUN 的 DNS 劫持仍会接管查询并返回 Fake-IP。
  Fix: 同时配置 Fake-IP 排除和公司 Nameserver 策略，不能只改 macOS 代理绕过列表。
  Prevention: 内网排障必须同时检查系统代理层、DNS 层和 TUN 路由层。

- Symptom: 加入 `*.chehejia.com` 后 `gerrit.it.chehejia.com` 仍返回 Fake-IP。
  Cause: Mihomo `DomainTrie` 中 `*` 只匹配一个标签，多级子域名没有被完整覆盖。
  Fix: 使用 `+.chehejia.com`，并可为关键入口增加精确域名兜底。
  Prevention: 对企业根域统一使用 `+.` 后缀语义，不用 `*.` 猜测多级匹配行为。

- Symptom: Fake-IP 消失了，但查询变成公网 `NXDOMAIN`，Authority 指向 `vip3.alidns.com`。
  Cause: 公司 DNS 查询仍走入 TUN，或 Nameserver 策略先命中了 `geosite:cn` 公网 DNS。
  Fix: 为公司 DNS 增加 `#en0`，并删除或后移 `geosite:cn`，确保公司规则先命中。
  Prevention: Nameserver 策略按顺序审计；泛化规则必须放在企业专用规则之后。

- Symptom: `dig @10.122.8.16` 看似查询了公司 DNS，却仍返回公网结果。
  Cause: TUN 配置 `dns-hijack: any:53` 会劫持指定服务器的 53 端口查询，命令中的 `SERVER` 字段不能单独证明真实上游路径。
  Fix: 使用 `dig -b <en0 IP> @<corp DNS>` 验证，或给 FlClash 上游配置增加 `#en0`。
  Prevention: 同时检查 `route -n get <corp DNS>` 和 DNS Authority，不根据 `dig SERVER` 一项下结论。

- Symptom: 直接修改 `defaults` 或 `config.yaml` 后重启，规则又退回旧值。
  Cause: FlClash 运行时内存配置会重新生成 `config.yaml`，并可能覆盖外部写入的 plist。
  Fix: 通过 FlClash 设置 UI 保存配置；外部文件只用于诊断和核对。
  Prevention: 将“偏好设置、生成的 config.yaml、运行中 core”视为三层状态，修改后逐层验证。

- Symptom: 自动化关闭或重启 FlClash 导致系统代理/DNS残留，扩大故障范围。
  Cause: 非正常退出可能来不及恢复系统网络设置，而且重启行为超出用户期望。
  Fix: 需要重启时停止工作，由用户手动重启并确认后继续验证。
  Prevention: 本机 FlClash 运维的固定边界是“代理不自动重启 FlClash”。

## Artifacts

- Logs: `~/Library/Application Support/com.follow.clash/traffic_analysis.jsonl`
  - 关键字段：`host`、`destinationIP`、`remoteDestination`、`processPath`、`rule`、`rulePayload`、`chains`。
- Outputs: `~/Library/Application Support/com.follow.clash/config.yaml`
  - 核对 `dns.fake-ip-filter` 与 `dns.nameserver-policy`。
- Source: `lib/common/task.dart`
  - 域名规则必须排在应用访问控制的 `PROCESS-PATH-REGEX` 前面，确保公司域名 `DIRECT` 可以覆盖 Chrome 的整应用代理。
- Source: `lib/common/system.dart`、`lib/controller.dart`
  - 退出时按顺序停止系统代理和 Core、重置 DNS、刷新缓存并验证；失败时显示手动命令并支持一键复制、重试或仍然退出。
- Tests: `test/common/task_test.dart`、`test/common/system_test.dart`
  - 覆盖域名规则优先级、带空格的 macOS 网络服务名、代理/DNS 输出解析和失败命令生成。
- Persisted settings: `~/Library/Preferences/com.follow.clash.plist`
  - 使用 `defaults read com.follow.clash flutter.config | jq ...` 读取，避免直接编辑二进制 plist。
- Backup: `~/Library/Application Support/com.follow.clash/backups/20260713-company-intranet/`
- Commands: 本文 `Solving Steps` 中的 `scutil`、`ipconfig`、`dig`、`route`、`curl` 命令。

## Notes

- `ssl_verify=0` 表示 curl 的证书校验成功，不是跳过校验；最终验收命令不要使用 `-k`。
- 系统 DNS 显示为 `223.5.5.5` 不一定代表公司策略无效；在 DNS 劫持开启时，应以目标域名的实际答案和 Nameserver 策略为准。
- `route -n get 10.132.59.191` 可能仍显示 `utun`，但未被应用级代理规则覆盖的请求可以由 Clash `DIRECT` 正常转发；最终判断以流量规则和 HTTPS 结果为准。
- 如果 Safari 已恢复而 Chrome 仍失败，检查 `traffic_analysis.jsonl` 是否显示 Chrome 命中 `PROCESS-PATH-REGEX` 并进入代理节点。本案例的持久修复是让 `lib/common/task.dart` 生成规则时把域名规则放在应用访问控制规则之前，同时在“域名”一级页面添加 `DOMAIN-SUFFIX,chehejia.com,DIRECT` 和 `DOMAIN-SUFFIX,chj.cloud,DIRECT`。
- 退出 FlClash 不能依赖固定延时后强退。退出链路应验证 HTTP/HTTPS/SOCKS 代理已关闭、默认网络服务已恢复 DHCP DNS、`198.18.0.1` Fake-IP 虚拟接口已释放；失败对话框必须展示并可复制手动重置 DNS 与验证命令。
- 公司 DNS 或网卡地址可能变化，复用时必须重新读取 DHCP；不要永久假设 `10.122.8.16/17` 和 `en0` 在其他环境仍成立。

## Tags

- macOS
- FlClash
- Mihomo
- corporate-intranet
- DNS
- Fake-IP
- TUN
- nameserver-policy
- en0
- Gerrit
