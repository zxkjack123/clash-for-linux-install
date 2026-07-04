# Changelog
## [2.5.19] - 2026-07-04

### 🔀 Routing
- **Zoom SJC media signalling wildcard** (`resources/mixin.yaml`): added `DOMAIN-SUFFIX,sjc.zoom.us,PROXY` to cover all San Jose datacenter Zoom media-signalling servers with random hostnames (e.g. `zoomsjcbb24mmr`, `zoomsjcaa11mmr`).
  - Root cause: `zoomsjcbb24mmr.sjc.zoom.us` (144.195.27.24:443) suffered 22 TCP i/o timeouts in 8 min during a meeting (2026-07-03 15:43–15:51), causing audio dropouts while video/screenshare remained unaffected.
  - DNS scan confirmed `zoomsjc*.sjc.zoom.us` naming is unpredictable (random suffix); `DOMAIN-SUFFIX` wildcard is the only reliable forward-coverage.
  - Also added explicit `DOMAIN,zoomsjcbb24mmr.sjc.zoom.us,PROXY` for the confirmed-offending host.

### 🔧 System
- **UDP buffer tuning** (`/etc/sysctl.d/90-zoom-udp.conf`): raised `net.core.rmem_{default,max}` and `net.core.wmem_{default,max}` from 208KB → 512KB to reduce `RcvbufErrors` on real-time Zoom UDP audio streams. 30-minute monitoring confirmed buffer errors stopped accumulating post-change.

### ✅ Verification
- 30-minute continuous Zoom network monitoring (57 rounds × 30s): 0 UDP interruptions, 0 audio dropouts, 0 mihomo errors, 0 PipeWire xruns.
- Full DNS scan of Zoom naming patterns across 8 datacenters (sjc/nyc/ams/fra/nrt/sin/syd/gru/bom) and us01–us10 regional prefixes.
- mihomo config test pass, runtime 267 rules, 8 proxy groups, all critical rules present.

## [2.5.18] - 2026-07-02

### 🔀 Routing
- **Zoom endpoint PROXY routing** (`resources/mixin.yaml`): routed 5 Zoom international (us06 datacenter) endpoints through PROXY (JP-Tailscale) to fix intermittent timeouts and reduce latency.
  - **Latency fix**: `us06polling.zoom.us` (DIRECT 2.24s → PROXY ~1.6s, -28%), `docs.zoom.us` (DIRECT 0.95s → PROXY ~0.96s)
  - **Timeout fix**: `zoomsjcbm213zc.sjc.zoom.us`, `us02images.zoom.us`, `aw1pmcapi.zoom.us` — confirmed flapping on 2026-07-01 via `journalctl` analysis
  - Conservative approach: only 5 of 16 Zoom servers proxied; 11 remain DIRECT with sub-second latency
  - All rules use `DOMAIN` exact match to avoid broad `DOMAIN-SUFFIX,zoom.us` side effects
- **Go ecosystem PROXY routing** (`resources/mixin.yaml`): routed `golang.org` / `proxy.golang.org` / `sum.golang.org` / `go.dev` / `godoc.org` through PROXY. These Google-hosted domains are unreachable from mainland China (TCP timeout / TLS SNI block), breaking `go build`, `go test`, `go mod download`.

### 🆕 New
- **`script/go-env.sh`**: Go environment setup script for mainland China. Sets `GOPROXY='https://goproxy.cn,direct'` (fast domestic mirror) with `GONOSUMCHECK=*` and `GONOSUMDB=*`. Two-layer approach: Clash proxy rules for import-path resolution + domestic mirror for module zip downloads. Source it with `source script/go-env.sh`.

### ✅ Verification
- Full A/B latency test: 16 Zoom endpoints tested DIRECT vs PROXY(JP-Tailscale), 3-round sampling
- Full proxy health suite: 13 critical services (GitHub, Google, OpenAI, DeepSeek, Docker, etc.) all ✅
- Zoom stress test: 5-round stability sampling on worst-case endpoints, 0 TCP-layer failures
- `journalctl` audit: 64 Zoom connections over test period, 0 errors/warnings/timeouts
- Go: all 5 domains confirmed reachable via PROXY (golang.org 301, proxy.golang.org 200, sum.golang.org 200, go.dev 200, godoc.org 301), goproxy.cn verified 200

## [2.5.17] - 2026-06-28

### 🔀 Routing
- **UIUIAPI domain migration** (`resources/mixin.yaml`): replaced deprecated `sg.uiuiapi.com` with `api.uiuihao.com`; added `DOMAIN-SUFFIX,uiuihao.com,PROXY` rule. The old domain is no longer reachable.
- **Removed no_proxy bypass** for UIUIAPI: the new `api.uiuihao.com` domain routes correctly through Clash proxy, eliminating the shell-level bypass workaround.

### 🛠 Fixes
- **`vpn-tools/`**: updated all hardcoded `sg.uiuiapi.com` references in `test_ai_connectivity.sh`, `quick_ai_test.sh`, `network_connectivity_test.sh`, `network_health_monitor.sh` → `api.uiuihao.com`.

### 🤖 Infrastructure
- **`.opencode/`**: established project-level opencode configuration with dedicated `clash-admin` primary agent for clash proxy administration.

### ✅ Verification
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- `api.uiuihao.com` verified: HTTP 200 via proxy (PROXY[JP-Tailscale]), `/v1/models` API returns 300+ models
- `sg.uiuiapi.com` confirmed unreachable (HTTP 000, timeout) — deprecated upstream

## [2.5.16] - 2026-06-14

### 🔀 Routing
- **MATCH default flip: PROXY → DIRECT** (`script/clashctl.sh`): the fallback rule now defaults to `DIRECT` instead of `PROXY`, making domestic/intranet sites route directly without needing individual rules. Controlled via `CLASH_MATCH_GROUP` env var; DIRECT/REJECT/REJECT-DROP bypass the proxy-group existence check.
- **GFW-blocked sites fixed PROXY rules**: added 9 `DOMAIN-SUFFIX` rules for `google.com`, `googleapis.com`, `gstatic.com`, `youtube.com`, `ytimg.com`, `gmail.com`, `bbc.com`, `reddit.com`, `x.com`, `duckduckgo.com` — now hard-coded to `PROXY` instead of relying on the old MATCH→PROXY default.
- **Existing PROXY rules hardened**: Wikipedia/Wikimedia/Wikidata/Microsoft/VS Code rules also hard-coded to literal `"PROXY"` instead of `strenv(CLASH_MATCH_GROUP)` to survive the default flip.

### ✅ Verification
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- Full routing audit: 54 domains across 6 categories all verified ✅ (DIRECT for domestic/institutional/AI/collaboration, PROXY for GFW-blocked, dedicated groups for dev/academic)
- `MATCH,DIRECT` confirmed live in runtime; all 9 new PROXY rules active

## [2.5.15] - 2026-05-10

### ✨ New
- **Domestic office/collaboration platforms DIRECT routing** (`resources/mixin.yaml`): add 34 `DOMAIN-SUFFIX` rules covering Feishu/Lark (飞书), DingTalk (钉钉), WPS/Kingsoft (金山办公), WeChat Work/WeCom (企业微信), Tencent Docs/Meeting (腾讯文档/会议), Yuque (语雀), Teambition, Zhihu (知乎), Wolai (我来), FlowUs, Huawei WeLink, Maimai (脉脉), and 163/Netease (网易邮箱/有道). Prevents proxy-induced latency spikes, TLS handshake delays, and geo-block 403s on domestic office services.

### ✅ Verification
- `bash -n $(git ls-files '*.sh')` — 0 syntax errors
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- `bash script/run_static_gates.sh` — all gates passed (0 high / 0 medium / 0 low)
- mihomo runtime rebuilt & restarted: all new domains confirmed `DomainSuffix → DIRECT` in logs

## [2.5.14] - 2026-04-23

### ✨ New
- **CAS / ASIPP intranet routing** (`resources/mixin.yaml`): force `IP-CIDR,202.127.200.0/21` (HFCASNET) and `IP-CIDR,159.226.0.0/16` (CAS Beijing CNIC) to `DIRECT`; add `DOMAIN-SUFFIX` rules for `ipp.cas.cn`, `cas.cn`, `ipp.ac.cn`, `hfcas.ac.cn`. Prevents Clash from diverting CAS/ASIPP intranet traffic to a proxy egress (off-campus access still requires ASIPP VPN if the target enforces source-IP allowlist).
- **`script/clashctl.sh`**: add `ipp.ac.cn` / `.ipp.ac.cn` to `no_proxy_addr` so curl/wget bypass the local Clash proxy for ASIPP intranet hosts.
- **`vpn-tools/network_health_check.sh`**: add `--no-notify` flag to suppress desktop alerts (useful for cron-driven probes that should only update state without spamming notifications).
- **OpenSSH-over-Tailscale migration plan** (`.github/plans/migrate-to-openssh-over-tailscale.md`): full execution record migrating jp/us/SynologyNAS923 nodes from `tailscale --ssh` (userspace SSH on :22) to OpenSSH with publickey auth. Coexistence achieved on jp-node via `Port 22 + Port 2222`; us-node and NAS use OpenSSH on :22 (no Tailscale --ssh interception).

### 🛠 Fixes
- **`vpn-tools/alert_notification.sh`**: strip dynamic numeric values from rate-limit message keys (e.g. `fails=52 zero=3` → `fails=N zero=N`) so health alerts that differ only in counters share one suppression bucket; use single `notify-send` replace-id (99900) and `-e` (transient) so new alerts replace prior bubbles instead of stacking during WARN→CRIT cycling.

### ✅ Verification
- `bash -n $(git ls-files '*.sh')` — 0 syntax errors
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- `bash script/run_static_gates.sh` — all gates passed (0 high / 0 medium / 0 low)
- `ssh jp 'echo OK'` / `ssh us 'echo OK'` / `ssh nas 'echo OK'` — all return OK via publickey auth
- `tailscale status` — jp/us direct paths, NAS via DERP-hkg (1 ms RTT)

## [2.5.13] - 2026-04-14

### ✨ New
- **`vpn-tools/network_health_check.sh`**: lightweight Nagios-style three-state health check (OK/WARN/CRIT) for GitHub, Copilot, and VS Code link probing via cron. Features configurable thresholds, streak-based debounce (consecutive failures before escalation), JSON state persistence, `--json` / `--verbose` / `--dry-run` / `--reset` flags, and integration with `alert_notification.sh` for desktop alerts.

### 🛠 Fixes
- **Block link-local IMDS probes**: added `IP-CIDR,169.254.0.0/16,REJECT,no-resolve` to `resources/mixin.yaml`. VS Code extensions continuously probe `169.254.169.254` (cloud instance metadata) on physical workstations; these requests were routed through the proxy, timing out and inflating `fails_5m` by ~976/hour.

### ✅ Verification
- `bash -n $(git ls-files '*.sh')` — 0 syntax errors
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- `bash script/run_static_gates.sh` — all gates passed (0 high / 0 medium / 0 low)
- Health check tested: OK (exit 0), WARN (exit 1), CRIT (exit 2), debounce escalation, recovery, cron auto-fire

## [2.5.12] - 2026-04-14

### 🛠 Fixes
- **Division-by-zero guards**: `check_streaming_services()` and `check_domestic_sites()` now handle zero-endpoint cases gracefully instead of crashing.
- **Unstable-skip latency inflation**: unstable endpoints marked as SKIP no longer contribute their timeout penalty to average latency calculations in `check_ai_services()` and `check_dev_services()`.
- **Cron overlap at :00**: removed duplicate `0 * * * * --check-only` cron entry that collided with the `*/10 --auto-fix` schedule every hour.
- **Atomic JSON write**: `health_metrics.json` is now written via tmp+mv to prevent partial reads from concurrent consumers.
- **SCNET routing**: changed from proxy to `direct` (domestic API, ~99 ms vs ~300–500 ms through proxy).

### 🔧 Improvements
- **Graduated latency scoring**: replaced binary pass/fail latency thresholds with a piecewise-linear `_grad_latency_score()` model (overseas 300–1500 ms, domestic 100–500 ms), yielding more representative health grades.
- **Faster failover detection**: AUTO proxy group `interval` reduced from 120 s to 30 s across all url-test groups, cutting node-down detection from ~2 min to ~30 s.
- **Notification auto-dismiss**: `notify-send` alerts now auto-close after 15 s (`-t 15000`).
- **Kimi endpoint removed**: no longer probed (service discontinued).
- **Semantic Scholar marked unstable**: excluded from availability scoring; failures no longer drag down health grade.

### 🐛 Script quality
- Generalized `sanitize_runtime.sh` hijack detection (no longer hardcodes vendor names).
- Fixed unquoted array slices in `optimize_ai.sh`, `test_ai_connectivity.sh`, and `test_openxlab_direct_rules.sh`.
- Fixed unsafe `xargs` in `clashctl.sh` (handles filenames with spaces).
- Added post-merge structural YAML validation in `clashctl.sh`.
- Added YAML fallback validation + `flock` in `update_clash_subscription.sh`.
- Subscription refresh systemd service: added `network-online.target` dependency.
- `uninstall.sh` now cleans up subscription refresh timer/service.

### ✅ Verification
- `bash -n $(git ls-files '*.sh')` — 0 syntax errors
- `bash tests/run_tests.sh` — 69 passed, 0 failed
- `bash script/run_static_gates.sh` — all gates passed (0 high / 0 medium / 0 low)
- Live health check: 87/B (was ~69/D under old scoring model)

## [2.5.11] - 2026-04-04

### ✨ New
- Added `vpn-tools/enable_vscode_fallback_direct.sh`: one-click toggle for VS Code direct-connect fallback when proxy is unavailable.
- Port-conflict management framework: new `CLASH_PORT_POLICY` (strict / random / auto), `CLASH_RESERVED_PORTS`, and per-port env vars (`CLASH_RESERVED_HTTP_PORT`, etc.) for flexible port allocation and collision avoidance.
- `runtime_guard.sh`: port-occupancy and port-drift checks (`CLASH_GUARD_CHECK_PORTS=1`) with customizable process allow-list (`CLASH_ALLOWED_PORT_PROCS_REGEX`).
- `clashctl.sh`: live proxy-port detection from controller API (`_get_proxy_port_live_from_controller`).
- Amazon domain family added to `resources/mixin.yaml` proxy rules (avoids anti-bot 503 / SSL timeouts on direct connections from China).

### 🛠 Fixes
- `install.sh`: fail-fast on `tar` extraction errors; robust `yq` binary rename using array glob instead of bare wildcard.
- `repair_subscription_and_restore.sh`: gracefully handle missing `pyyaml` (exit 2 + warning instead of crash); harden SS-URI parsing against malformed URLs; fix `skip-cert-verify` default to `false`.
- `emergency_off.sh`: fix gsettings rollback quoting (strip stray single-quote chars from saved mode value).
- `vpn-tools/optimize_vscode_copilot.sh`: switch service-check data format from pipe-delimited to tab-delimited, fixing fragile `IFS='|'` parsing and ensuring correct proxy-mode fallback.
- `vpn-tools/network_health_monitor.sh`: fix countdown loop direction (`seq 0 9` not `9 -1 0`); initialize associative array before first use.
- `vpn-tools/network_dashboard.sh`: fix bracket-glob escaping in regex substitution.

### 🔧 Improvements
- `systemd/clash-subscription-refresh.service`: replace `network-online.target` dependency with `default.target`; add `Restart=on-failure` with rate limiting (3 retries / 1 hour, 5 min delay).
- `script/ensure_system_proxy_best_practices.sh`: new `_reserved_port_issue_if_any` for system-proxy port-safety validation.
- `script/common.sh`: port-reservation helpers (`_clash_reserved_ports_list`, `_clash_is_reserved_port`, `_clash_port_policy`, `_port_conflict_report`).
- `docs/installation/ENV_CONFIG_GUIDE.md`: document all new port-policy and guard env vars.

### 📋 Reviews & plans (not shipped as code)
- `.github/reviews/network-jp-tailscale-2026-04-03.md`: JP-node connectivity assessment pre-migration.
- `.github/reviews/network-stability-30min-2026-04-04.md`: 35-minute continuous monitoring report (post Shadowsocks migration; verdict: STABLE 9.35/10).
- `.github/plans/bug-audit-remediation-2026-03-26.md`: tracked bug-audit remediation plan.
- `.github/reviews/bug-hunt-2026-03-26.md`: code-quality bug-hunt review.

### ✅ Verification
- `bash -n $(git ls-files '*.sh')` — 0 errors
- `bash script/run_static_gates.sh` — all gates passed (0 high / 0 medium / 0 low)
- `script/clash_diagnose.sh --fast --json` — exit_status 2 (all core checks OK)
- `script/runtime_guard.sh --check --json` — grade A, 0 issues

## [2.5.10] - 2026-03-02

### 🔒 Security & hardening
- Eliminated predictable `/tmp` state/temp artifacts across scripts by moving them to a per-user state directory (prefers `$XDG_RUNTIME_DIR`, falls back to `~/.local/share/clash`) while keeping legacy cleanup where needed.
- Safer JSON payload construction for controller selector switching and webhook notifications (proper string escaping; uses `jq` when available).

### 🛠 Fixes
- Subscription refresh automation is now effective: `script/refresh_subscription_direct.sh` applies changes and restarts (`--apply --restart`).
- `systemd/clash-subscription-refresh.service` now targets the installed path (`%h/.local/share/clash`) and avoids an `[Install]` section to prevent accidental login-trigger refresh.
- `install.sh` / `uninstall.sh` now fail fast when not run from the repository root; systemd unit `ExecStart` paths are properly quoted.

### 🧪 Diagnostics & developer tooling
- Added a comprehensive audit write-up: `docs/development/BUG_AUDIT_2026-03-01.md`.
- Improved static gate accuracy for heredoc and multiline block detection in audit scripts.

## [2.5.9] - 2026-02-06

### ✨ New
- Added a small "static gates" toolkit for repo-wide reliability checks:
  - `script/audit_errexit_arith.py`: flags `((var++))` / `((var--))` foot-guns under `set -e`.
  - `script/audit_json_stdout_purity.py`: checks that JSON mode keeps stdout **JSON-only** (logs go to stderr).
  - `script/run_static_gates.sh`: one-shot runner for all static gates.

### 🛠 Fixes
- Hardened Docker proxy testing and demos against hangs by ensuring container-side `curl` calls always include a total timeout (`--max-time`) and consistent connect timeouts.

### 🔧 Improvements
- `.gitignore`: ignore Python transient artifacts (`__pycache__/`, `*.pyc`) generated by audit scripts.

### ✅ Verification
- `bash script/run_static_gates.sh`
- `bash -n $(git ls-files '*.sh')`
- JSON smoke: `script/clash_diagnose.sh --fast --json` / `script/runtime_guard.sh --check --json`

## [2.5.8] - 2026-02-05

### ✨ New
- Added `docs/integrations/RESEARCH_ACADEMIC_PROFILE.md`: a minimal **JP-only** dev/academic routing profile (Copilot / Docker / Scholar / common publishers).
- `resources/config.yaml` now ships a JP-only template with observable groups (`DEV` / `COPILOT` / `DOCKER` / `ACADEMIC`) while keeping a conservative default (`MATCH,DIRECT`).

### 🛠 Fixes
- Safer controller UX and secret handling:
  - `script/clashctl.sh`: added `clashctl secret init` (generates a random secret, writes to `~/.local/share/clash/controller.secret`, updates `mixin.yaml`, and restarts; never prints secrets).
  - `script/common.sh`: when `external-controller` port is occupied, reassigns the port while preserving the original bind host (avoids accidental `0.0.0.0` exposure).
- Diagnostics and dev checks refreshed for split-port setups:
  - `script/clash_diagnose.sh`: clearer guidance for secret init and localhost-only controller defaults.
  - `vpn-tools/quick_vpn_check.sh`: improved developer endpoint coverage and port/controller auto-detection.

### 🔧 Improvements
- `resources/mixin.yaml` is now an empty map (`{}`) by default, keeping this fork’s “config.yaml as the single source of truth” workflow predictable.

### ✅ Verification
- `bash -n` on changed shell scripts
- `mihomo -t` on `resources/config.yaml` and the active `~/.local/share/clash/runtime.yaml`
- `script/clash_diagnose.sh --fast --json`

## [2.5.7] - 2026-01-27

### ✨ New
- Added `vpn-tools/enable_copilot_fallback_direct.sh`: a preview-first helper to create/update a dedicated `COPILOT` **fallback** group (`JP-Tailscale` → `DIRECT`) in `~/.local/share/clash/mixin.yaml`, with an optional rebuild/restart path.

### 🛠 Fixes
- `install.sh`: resource copy is now safe for spaces/newlines in filenames (switched to `find -print0 | xargs -0`), and still skips large archives/images.
- `vpn-tools/trace_mihomo_connections.sh`: improved controller parsing and output robustness (stable delimiter + id-based dedupe), and correctly sends the Authorization header when `secret` is set.
- `vpn-tools/network_change_probe.sh`: more resilient connectivity probing and reporting (reduces false positives in noisy networks).

### 🔧 Improvements
- `script/sanitize_runtime.sh`: Copilot domain rules are injected as **high-priority** rules (ahead of broad GitHub rules). If a `COPILOT` group exists, Copilot routes to it; otherwise it safely falls back to `DIRECT`.
- `script/clashctl.sh`: expanded `NO_PROXY`/GNOME ignore-hosts to include Tailscale control-plane domains (`tailscale.com`, `.tailscale.com`, `controlplane.tailscale.com`) so tailnet control traffic remains DIRECT.

### ✅ Verification
- `bash -n` on changed shell scripts
- `script/clash_diagnose.sh --fast --json`

## [2.5.6] - 2026-01-23

### ✨ New
- Added `script/emergency_off.sh`: a safe-by-default “one-click DIRECT fallback” tool that stops user services and unsets system proxy (supports `--dry-run` and `--trial` rollback).
- Added `vpn-tools/use_jp_tailscale_only.sh`: a preview-first helper to prune subscription nodes from `~/.local/share/clash/mixin.yaml` and converge proxy-groups to **JP‑Tailscale-only** (optional rebuild/restart).

### 🛠 Fixes
- `vpn-tools/test_docker_proxy.sh`: removed `eval` execution by switching to argv-based command invocation; fixed negative-test semantics so “expected fail” checks no longer count as failures.
- `script/clash_diagnose.sh --json`: now emits **JSON only on stdout** (human-readable report goes to stderr) so it can be reliably piped into parsers.

### 🔧 Improvements
- `script/runtime_guard.sh`: hardened alert hook handling:
  - Prefer safe modes via `--alert none|log|notify|webhook|script` and `--alert-script` + repeated `--alert-arg`.
  - Legacy `--alert-cmd/ALERT_CMD` remains available only behind an explicit unsafe opt-in.
- Docs refreshed to match the new safe defaults (Docker host networking guidance; runtime guard alert examples).

### ✅ Verification
- `bash -n` on repo shell scripts
- `script/clash_diagnose.sh --fast --json`
- `script/runtime_guard.sh --check --json`

## [2.5.5] - 2025-12-22

### ✨ New
- Added SZAI MinerU endpoint `c-2002916625925693441.szai.scnet.cn:58043` to the SCNET/QDAI DIRECT pin set (kept ahead of `DOMAIN-SUFFIX,cn` style catch-alls).

### 🛠 Fixes
- Hardened `script/sanitize_runtime.sh` to repair historical `runtime.yaml` rule corruption where multiple rules were accidentally concatenated into a single YAML list item (e.g. `...,DIRECT DOMAIN,...` leading to mihomo parse errors like `proxy [DIRECT DOMAIN] not found`).

### 🔧 Improvements
- `vpn-tools/network_connectivity_test.sh` now includes coverage for the new SZAI MinerU endpoint.

### ✅ Verification
- `bash -n` on changed shell scripts

## [2.5.4] - 2025-12-19

### ✨ New
- Added `vpn-tools/trace_mihomo_connections.sh` to live-trace mihomo controller `/connections` and prove whether VS Code/Copilot traffic is reaching mihomo, including the matched `rule` and final `chains`.
- Added VS Code core-domain and JP-Tailscale single-node testing utilities (see `vpn-tools/test_vscode_core_domains.sh` and `vpn-tools/jp_tailscale_single_node_test.sh`) for repeatable success-rate/latency validation.

### 🔧 Improvements
- VS Code/Copilot optimization tooling now supports hardened controller setups:
  - `vpn-tools/optimize_ai.sh` auto-detects `external-controller` + `secret` from `~/.local/share/clash/runtime.yaml` and sends the Authorization header when required.
  - `vpn-tools/optimize_vscode_copilot.sh` continues through connectivity tests even when AI optimization cannot complete (reduces “one failure stops everything” behavior).
- Subscription refresh robustness: `systemd/clash-subscription-refresh.service` raises `TimeoutStartSec` to 45 minutes for slow providers.

### 🛠 Fixes
- `.gitignore` now ignores the repo-root `tmp/` scratch folder (transient diagnostics / ad-hoc artifacts).

### ✅ Verification
- `bash -n` on all changed shell scripts
- `script/clash_diagnose.sh --fast --json`
- `script/runtime_guard.sh --check --json`
- `vpn-tools/optimize_vscode_copilot.sh`
- `vpn-tools/trace_mihomo_connections.sh --seconds 2`

## [2.5.3] - 2025-12-06

### 🔧 Improvements
- `resources/mixin.yaml` now pins the SZ MinerU endpoint `c-1996024701209694210.szai.scnet.cn:58043` to DIRECT alongside other SCNET/QDAI hosts, and keeps SCNET/QDAI DNS policies preferring public recursors before campus resolvers to avoid REFUSED/NXDOMAIN when off-net.
- `script/clashctl.sh` writes a unified `no_proxy` state (including SCNET/QDAI/SZAI, Tailscale, LAN) to `/tmp/.clash_no_proxy` and propagates the same bypass set into GNOME ignore-hosts so curl/pdf2md and GUI apps consistently bypass the proxy for campus domains.
- `vpn-tools/network_connectivity_test.sh` adds explicit SCNET MinerU SZ coverage and refreshed labels, keeping the quick/full matrices aligned with the new endpoints.
- `docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md` clarifies that shells should reuse `/tmp/.clash_no_proxy` for the curated bypass list emitted by `clash-proxy-env.service` instead of hardcoding domains.

### ✅ Verification
- `vpn-tools/network_connectivity_test.sh full`

## [2.5.2] - 2025-12-05

### ✨ New
- Added `script/refresh_subscription_direct.sh` plus user-level systemd units (`clash-subscription-refresh.service/.timer`) and an end-to-end guide (`docs/installation/AUTO_SUBSCRIPTION_REFRESH.md`) so subscriptions can refresh every day without inheriting proxy variables. Optional post-refresh optimization is built in.
- Introduced `vpn-tools/optimize_dev_nodes.sh` to benchmark GitHub / NPM / PyPI / Docker endpoints and auto-switch the best node across groups. The tool is documented in both `README.md` and `vpn-tools/README.md`.
- Published `docs/development/JP_PERSONAL_PROXY_NODE.md`, a full walkthrough for building a personal JP exit via Tailscale + sing-box; linked from the docs index.

### 🔧 Improvements
- `resources/mixin.yaml` and `resources/config.yaml` now pin the entire `*.scnet.cn` / `*.szai.scnet.cn` / `*.qdai.scnet.cn` surface (including `c-1996024701209694210.szai.scnet.cn:58043`) to DIRECT, keeping the SCNET rule block ahead of `DOMAIN-SUFFIX,cn`. The sanitizer reorders these rules automatically, and `script/clashctl.sh` exports the same domains inside `no_proxy`/`NO_PROXY` so curl/pdf2md bypasses the proxy as well.
- `vpn-tools/quick_ai_test.sh`, `test_ai_connectivity.sh`, `network_connectivity_test.sh`, `network_health_monitor.sh`, `optimize_all_network.sh`, `show_vpn_status.sh`, and related docs now point SiliconFlow checks at `https://siliconflow.cn/` and OpenRouter at `https://openrouter.ai/api/v1/*` to match the current production endpoints.
- `vpn-tools/README.md` and the top-level README now highlight the new Dev optimization workflow so it is part of the recommended daily toolkit.
- `.gitignore` ignores the subscription refresh log that the new automation produces.

### 🛠 Fixes
- Hardened the `速云梯` policy groups in both config sources so URL-test selectors keep working even after provider refactors.
- `docs/development/SILICONFLOW_FIX.md` reflects the updated SiliconFlow health check URL to avoid false negatives when copying commands from the guide.

### ✅ Verification
- `vpn-tools/network_connectivity_test.sh full`

## [2.5.1] - 2025-11-30

### 🛠 Fixes
- `vpn-tools/network_connectivity_test.sh` now auto-detects the controller endpoint directly from `~/.local/share/clash/runtime.yaml` (falling back to `127.0.0.1:9090` only when the runtime file is missing). This prevents false "Controller unreachable" warnings when users customize `external-controller` (e.g., port `9990`).
- Normalized controller strings (trim spaces/quotes, handle bare `:9990` notation) to keep the diagnostics output clean.
- Marked `script/clash_diagnose.sh` as executable so it can be launched without manual `chmod +x`.
- Updated all OpenRouter routing and docs references to use the active base domain `https://openrouter.ai/api/v1/*` (legacy `api.openrouter.ai` DNS has been retired). Existing DNS/rule entries keep the legacy host for compatibility, but the new domain now receives priority in `resources/mixin.yaml` and downstream consumers.

### ✅ Verification
- `vpn-tools/network_connectivity_test.sh full`

## [2.5.0] - 2025-11-20

### ✨ New
- **AI Connectivity Enhancements**:
  - Added support for **SCNET**, **UIUI**, **SiliconFlow**, and **OpenRouter** in connectivity tests and configuration.
  - Updated `resources/mixin.yaml` and `resources/config.yaml` with new rules and DNS policies for these AI services.
  - Created `vpn-tools/test_scnet_api.sh` for dedicated SCNET testing.
  - Updated `vpn-tools/test_ai_connectivity.sh` to include new endpoints.

### 🚀 Performance & Architecture
- **Shell Startup Optimization**:
  - Eliminated shell startup latency by removing synchronous `watch_proxy` checks from `.bashrc`.
  - Implemented a "Best Practice" architecture using a lightweight state file (`/tmp/.clash_system_proxy_state`) for instant shell environment setup.
  - Created `docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md` documenting the new architecture.
  - Updated `script/common.sh` to clean up legacy hooks and support the new pattern.

### 🔧 Improvements
- **Network Testing**:
  - `vpn-tools/network_connectivity_test.sh` now includes SCNET, UIUI, SiliconFlow, and OpenRouter in reachability checks.
  - `vpn-tools/test_ai_connectivity.sh` now supports a wider range of AI endpoints.

### ✅ Verification
- Verified shell startup is instant (0 overhead).
- Verified proxy connectivity to Google, YouTube, and new AI endpoints.
- Verified systemd services (`mihomo`, `clash-proxy-env`) function correctly with the new architecture.

## [2.4.6] - 2025-11-19

### 🔧 Tooling
- `vpn-tools/test_docker_proxy.sh` now auto-detects the active `mixed-port` and `external-controller` values from `~/.local/share/clash` (runtime/config/mixin). This prevents false failures when the controller isn’t bound to the legacy `9090` port and respects custom LAN bindings out of the box.
- Ports can be overridden per run via `CLASH_PROXY_PORT` / `CLASH_API_PORT` environment variables for remote or non-standard setups.

### 📚 Docs
- Updated `vpn-tools/DOCKER_PROXY_TESTING_ENHANCED.md` to describe automatic port detection and the new override flags for advanced scenarios.

### ✅ Verification
- Executed `vpn-tools/test_docker_proxy.sh` with controller on `9990` and proxy on `7890`. Pre-flight now succeeds and the suite continues through the service matrix (remaining failures, if any, are due to real network timeouts such as `claude.ai`).

## [2.4.5] - 2025-10-24

### ✨ New
- One-click start/stop scripts:
  - `vpn-tools/start_vpn.sh` to start mihomo and apply system proxy safely (calls `clashctl on` and prints controller `/version`; legacy `clashon` remains available when sourcing helpers).
  - `vpn-tools/stop_vpn.sh` to stop the service and fully clean proxy settings (env, GNOME/KDE), leaving no residue.

### 🔧 Improvements
- Diagnostics coverage extended in `vpn-tools/quick_vpn_check.sh` and `vpn-tools/proxy_connectivity_report.sh`:
  - Added PyPI, PyPI Files, Docker Hub, Docker Registry (treat 401 as reachable), ProtonVPN Repo (treat 403 as reachable), and Copilot Proxy (treat 404 as reachable) endpoints.
- Dev routing hardening in `resources/mixin.yaml` and VS Code launcher env in `vpn-tools/fix_vscode_stale_proxy.sh`:
  - Ensure `api.github.com` and `github.com` go DIRECT to avoid flaky proxy paths for sign-in/API.
  - Add the same domains to `no_proxy` for VS Code sanitized launch.
- Utility: `vpn-tools/probe_domain_across_nodes.sh` now auto-detects controller port from `runtime.yaml` (`external-controller`), working with non-default ports (e.g. 9990).

### 🧹 Cleanup
- Removed stray temporary files created during ad-hoc runs (`Switch`, `; done`, resource `wget-log*`).
- Dropped duplicate `resources/config.yml` to avoid confusion with the canonical `resources/config.yaml`.

### ✅ Verification
- Verified service lifecycle via one-click scripts and `clashctl on/off` (with `clashon/clashoff` available as optional sourced helpers).
- Controller: http://127.0.0.1:9990, version `v1.19.2`; mixed-port `7890` for HTTP/SOCKS.
- Quick VPN Check: 13/13 (100%) GOOD on representative endpoints.


All notable changes to this project will be documented in this file.

## [2.4.4] - 2025-10-23

### 🛠 Fixes
- Restart tooling: `vpn-tools/restart_clash_service.sh` now resolves the repository root from its own location, fixing a path bug that caused the GNOME best-practice step to fail in certain working directories. The script reliably applies `script/ensure_system_proxy_best_practices.sh`.

### 🔧 Routing improvements
- VS Code Copilot stability: enforced DIRECT routing for Copilot endpoints in `resources/mixin.yaml` to avoid flaky proxy paths (SSE/HTTP2/WebSocket).
  - Added: `api.githubcopilot.com`, `api.individual.githubcopilot.com`, `copilot-proxy.githubusercontent.com`, and `*.githubcopilot.com` → `DIRECT`.
  - Removed conflicting `Development` routes for Copilot-specific domains (other GitHub dev traffic remains under `Development`).

### ✅ Verification
- Applied mixin → runtime merge and single restart via `clashctl` internal merge routine; GNOME ignore-hosts step confirmed as applied (idempotent).
- OpenXLab direct rules remained intact; service restart completed successfully.

## [2.4.3] - 2025-10-20

### 🛠 Fixes & Resilience
- Diagnostics: Fixed integer parsing in `script/clash_diagnose.sh` for 5-minute failure counter (no more `[[: integer expression expected]]`).
- Status: Hardened `vpn-tools/show_vpn_status.sh` to avoid early exit, add jq-less fallbacks, and tolerate missing groups.
- Quick check: Made `vpn-tools/quick_vpn_check.sh` GitHub API probe resilient with fallback endpoints and a UA header.

### ✨ Best-practices Automation
- New: `script/ensure_system_proxy_best_practices.sh` enforces GNOME ignore-hosts for LAN + Tailscale + MagicDNS.
- Integrated into `script/clashctl.sh` and `vpn-tools/restart_clash_service.sh` so best practices auto-apply when enabling/restarting proxy.

### ✅ Verification
- Clean runtime rules (removed legacy hijack for 1.1.1.1/8.8.8.8, ensured DIRECT). Service health verified post-restart.
- Quick checks: 100% on core proxy diagnostics; quick VPN score improved stability in mixed environments.

## [2.4.2] - 2025-10-18

### 🧹 Cleanup
- Minor housekeeping and version sync; no functional changes.

## [2.4.1] - 2025-10-18

### 🛠 Fixes
- Hardened Git/system proxy configuration to prevent malformed proxy URLs after reboot.
  - Ensured `clashctl.sh` always derives a valid port before writing Git proxy settings.
  - Added validation and safe fallback to avoid values like `127.0.0.1:` that break Git.

### ✅ Verification
- Verified `git ls-remote` and a full `git clone` to GitHub work correctly with the fixed logic.

## [2.4.0] - 2025-10-15

### 🧹 Cleanup & Standardization

#### Removed (Deprecated)
- Removed latency-only AI scripts: `vpn-tools/test_ai_simple.sh`, `vpn-tools/test_ai_nodes.sh`.
- Cleaned duplicated content in `vpn-tools/proxy_connectivity_report.sh`.
- Removed generated latency reports from version control; reports are now on-demand only.

#### Added
- Shared helper: `vpn-tools/lib/net_helpers.sh` consolidating curl/timeout, grading, percent, and symbol handling (emoji/ASCII fallback via `NH_ASCII=1`).

#### Updated
- Refactored quick scripts to use the helper and standardized symbols:
  - `vpn-tools/quick_ai_test.sh`
  - `vpn-tools/quick_streaming_test.sh`
  - `vpn-tools/proxy_connectivity_report.sh`
- `vpn-tools/README.md`: Documentation reflects on-demand reports.

#### Notes
- Executable bits ensured for diagnostics scripts.
- Summary-only full diagnostics run validated successful operation.

## [2.3.0] - 2025-10-14

### 📁 文档结构重组

#### ✨ 新增功能
- **创建结构化文档目录** (`docs/`)
  - `docs/installation/` - 安装和配置文档
  - `docs/network/` - 网络优化文档
  - `docs/integrations/` - 功能集成文档
  - `docs/development/` - 开发和调试文档
  - `docs/README.md` - 完整的文档导航和目录

#### 🔧 优化改进
- **主目录清理**：从 17 个文档减少到 5 个核心文档
  - 保留：README.md, CHANGELOG.md, QUICK_START.md, LICENSE, VERSION
  - 其他文档按功能分类移动到 docs/ 子目录

- **文档重新组织**：
  - 安装配置 (3个): USER_INSTALL_GUIDE, ENV_CONFIG_GUIDE, SECURITY
  - 网络优化 (2个): NETWORK_OPTIMIZATION_GUIDE, NETWORK_SYSTEM_REVIEW
  - 功能集成 (4个): AI_SERVICES, DOCKER_INTEGRATION, VSCODE_COPILOT_FIX
  - 开发调试 (5个): BUG_FIX_REPORT, UPDATE_NOTES, 等

#### 📚 文档增强
- README.md 新增文档导航表格
- 创建 docs/README.md 作为文档中心索引
- 所有文档保持完整历史记录（使用 git mv）

#### 🎯 改进效果
- ✅ 主目录更清晰，只保留核心文档
- ✅ 文档分类清晰，易于查找
- ✅ 新用户更容易理解项目结构
- ✅ 维护更方便，相关文档集中管理

---

## [2.2.0] - 2025-10-14

### 🔧 VSCode Copilot 网络诊断与优化

#### ✨ 新增功能
- **VSCode Copilot 专用优化工具** (`vpn-tools/optimize_vscode_copilot.sh`)
  - 自动检测 Clash 服务状态
  - 优化 AI 服务节点选择
  - 测试关键服务连接（GitHub API、Copilot API、OpenAI）
  - 检查代理环境变量和 VSCode 进程配置
  - 提供详细的诊断报告和建议

- **完整的诊断和解决方案文档** (`VSCODE_COPILOT_FIX.md`)
  - 网络问题深度分析（SSL 连接不稳定根因）
  - 5 种解决方案（从简单到高级）
  - 预防措施和定期优化建议
  - 常见问题 Q&A
  - 快速命令参考手册

#### 🐛 问题修复
- **诊断 GitHub Copilot API 连接不稳定问题**
  - 识别出新加坡节点到 Copilot API 的路由质量问题（80% 成功率）
  - SSL 握手偶尔超时，响应时间波动（1-6秒）
  - 网络健康分数 65/100 (等级 D)

#### 🔧 优化改进
- 自动选择最佳 AI 节点（V1-新加坡01 或 V1-美国10）
- 运行全网络优化，提升整体连接质量
- 增加 VSCode 进程代理配置检测
- 对比直连和代理连接性能

#### 📚 文档增强
- 详细的问题归属分析（客户端 vs 服务器端）
- 节点质量测试方法和工具
- VSCode 代理配置最佳实践
- 长期网络维护建议

#### 💡 使用建议
- 重启 VSCode 以应用新的网络配置
- 如问题持续，切换到美国节点（距离 GitHub 更近）
- 定期运行 `optimize_vscode_copilot.sh` 保持最佳性能
- 考虑增加 VSCode 超时设置降低敏感度

---

## [2.1.0] - 2025-10-13

### 🔒 Security & Configuration Enhancement

#### ✨ 新增功能
- **环境变量配置系统** - 实现统一的 `.env` 配置管理
  - 创建 `vpn-tools/load_env.sh` - 自动加载环境变量模块
  - 支持递归查找 `.env` 文件，自动导出配置
  - 包含错误处理和详细日志功能

- **API Key 安全管理**
  - 创建 `.env.example` 配置模板（包含详细注释）
  - 新增 `ENV_CONFIG_GUIDE.md` - 完整的环境变量配置指南
  - 更新 `SECURITY.md` - API key 安全管理最佳实践

#### 🔧 优化改进
- **脚本配置加载升级**
  - `network_health_monitor.sh` - 集成 `.env` 自动加载
  - `network_dashboard.sh` - 集成 `.env` 自动加载
  - `optimize_all_network.sh` - 集成 `.env` 自动加载
  - 所有监控脚本现在从环境变量读取配置，不再硬编码

- **Git 安全保护增强**
  - 更新 `.gitignore` 忽略所有敏感配置文件
  - 添加 `.env`, `*_api_keys.conf`, `*_secrets.conf`, `*.key`, `*.pem` 等
  - `.env` 文件权限自动设置为 600（仅所有者可读写）

#### 🐛 Bug 修复
- 移除 `AI_SERVICES_UPDATE.md` 中硬编码的 API key
- 改为从环境变量 `SILICONFLOW_API_KEY` 读取
- 清理历史代码中的敏感信息泄露

#### 📚 文档更新
- 新增 `ENV_CONFIG_GUIDE.md` - 环境变量配置完整指南
- 更新 `.env.example` - 详细的配置模板和使用说明
- 优化表格格式，提升文档可读性

#### 🔐 安全提升
- API keys 不再硬编码在代码中
- 敏感配置文件受 `.gitignore` 保护
- 完整的安全配置文档和最佳实践
- 支持多种配置方式（.env文件、环境变量、系统配置）

---

## [2.0.0] - 2025-10-13

### 🎉 Major Release - 网络监控系统全面升级

#### ✨ 新增功能
- **一键优化全网络** - 新增 `optimize_all_network.sh` 脚本，可一键执行所有网络优化任务
- **智能网络监控** - 新增 `network_health_monitor.sh`，提供全面的网络健康检查
- **可视化仪表盘** - 新增 `network_dashboard.sh`，实时显示网络状态和健康指标
- **智能规则优化** - 新增 `intelligent_rule_optimizer.sh`，自动分析并推荐最优规则
- **多渠道告警** - 新增 `alert_notification.sh`，支持桌面通知/Webhook/邮件
- **定时任务管理** - 新增 `setup_monitoring_cron.sh`，一键安装自动监控

#### 🔧 优化改进
- **AI服务监控定制化**
  - 移除地域限制的服务（OpenAI API, Claude, Anthropic, Gemini, DeepSeek）
  - 添加国内可用服务（ChatGPT网页版, UIUI-API, 硅基流动, Kimi）
  - AI服务成功率：25% → 100% (+300%)
  - AI服务延迟：1589ms → 862ms (-46%)

- **流媒体监控优化**
  - 移除Netflix（不常用）
  - 添加Google Meet
  - 保留YouTube和Zoom

- **健康评分系统**
  - 实现加权评分算法（AI 30%, Dev 25%, Streaming 20%, Domestic 25%）
  - 健康分数从54/100提升到71/100 (+31%)

#### 🐛 Bug修复
- 修复JSON文件被日志污染的问题（重定向log到stderr）
- 修复报告生成的heredoc引号问题
- 修复硅基流动API地址错误（404 → 200）
- 修复DeepSeek速率限制问题（改用Kimi）
- 修复jq空值处理问题（添加默认值）

#### 📚 文档完善
- 新增9个详细文档，覆盖使用、优化、修复等各个方面

#### 🎯 性能提升
- AI服务成功率: 25% → 100% (+300%)
- 健康分数: 54/100 → 71/100 (+31%)
- AI服务延迟: 1589ms → 862ms (-46%)

---

## [2025-08-13] - Service Startup Fix

### Fixed
- **Critical**: Fixed mihomo service startup timeout issue
  - Removed problematic `ExecStartPost` command that caused circular dependency
  - Added `TimeoutStartSec=30` to prevent long startup hangs
  - Updated clash-proxy-env.service to use `BindsTo` instead of `Requisite`
  - Added timeout protection to proxy environment service

### Changed
- **Service Configuration**: Improved systemd service reliability
  - Main service now starts faster and more reliably
  - Proxy environment service properly depends on main service
  - Better error handling and timeout management

### Technical Details
- The previous version had a circular dependency where:
  1. mihomo.service would start
  2. ExecStartPost would try to restart clash-proxy-env.service
  3. clash-proxy-env.service would wait for mihomo.service
  4. This caused a 90-second timeout and service failure

- The fix involves:
  1. Removing the ExecStartPost command from mihomo.service
  2. Using `BindsTo` dependency instead of `Requisite` in clash-proxy-env.service
  3. Adding appropriate timeouts to prevent hangs
  4. Allowing the proxy environment service to start independently

### Testing
- ✅ Proxy connectivity tested for local (China) and global sites
- ✅ Service starts reliably without timeouts
- ✅ Automatic restart functionality works correctly
- ✅ Web UI accessible at http://localhost:9090/ui
- ✅ All proxy groups and nodes functioning properly

## Previous Versions

### [Original] - User Space Installation
- Initial implementation of user-space Clash installation
- No sudo required for daily operations
- User systemd service management
- Automatic proxy environment setup
