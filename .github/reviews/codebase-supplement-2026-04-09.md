# Supplementary Repository Review: clash-for-linux-install

> Supplement to [codebase-2026-04-09.md](codebase-2026-04-09.md). That review's B1–B5, Q3, O2 are now fixed. This review covers deeper issues found in a second pass.

## Executive Summary
- New Findings: 3 🔴 / 6 🟡 / 3 🟢
- Focus Areas: `set -e` + `$?` pattern in test_ai_connectivity.sh, mixin merge error handling, subscription update flow, systemd unit hygiene, common.sh CWD assumptions

## ① Potential Bugs

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| B6 | 🔴 | `vpn-tools/test_ai_connectivity.sh:157` | `set -e` + `$?` | `awk -v v=$sr_tmp 'BEGIN{exit !(v<0.3)}'; [[ $? -eq 0 ]] && break` — under `set -euo pipefail`, when awk exits non-zero (condition false), script aborts before `$?` check. Early-break logic for low success rate never fires; script runs all rounds even when node is clearly bad. | Refactor to: `if awk -v v=$sr_tmp 'BEGIN{exit !(v<0.3)}'; then break; fi` |
| B7 | 🔴 | `vpn-tools/test_ai_connectivity.sh:181` | `set -e` + `$?` | `awk -v s=$s -v b=$best_score 'BEGIN{exit !(s>b)}'; [[ $? -eq 0 ]] && { best=$n; best_score=$s; }` — same class as B6. Best-node selection always picks the last node instead of the highest score because awk non-zero aborts before comparison logic runs. | Refactor to: `if awk -v s=$s -v b=$best_score 'BEGIN{exit !(s>b)}'; then best=$n; best_score=$s; fi` |
| B8 | 🟡 | `vpn-tools/test_ai_connectivity.sh:131` | Unquoted array init | `local arr=($(printf '%s\n' "$@" \| sort -n))` — unquoted command substitution in array init; word-splitting/globbing risk on malformed input. | Use `mapfile -t arr < <(printf '%s\n' "$@" \| sort -n)` |

## ② Code Quality Issues

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| Q6 | 🔴 | `script/clashctl.sh:543-557` | Silent merge failure | Mixin merge fallback path uses `\|\| true` on every yq operation (cp, eval-all, mv, yq -i). If merge partially fails, a half-merged config is written without error. Only empty file is caught. | Remove `\|\| true` from critical yq ops; let failure propagate to `_error_quit`. Add integrity check (e.g., verify `proxy-groups` key exists) after merge. |
| Q7 | 🟡 | `script/update_clash_subscription.sh:91` | Conditional validation | YAML parse validation only runs if `yq` is installed. Without `yq`, raw subscription response is written as config without any structural check. | Add fallback: at minimum check that file starts with valid YAML (e.g., `head -1` is not HTML/error page). |
| Q8 | 🟡 | `script/update_clash_subscription.sh:112` | No lock on config swap | No `flock` around fetch→backup→write path. Concurrent runs (manual + cron timer) can interleave and corrupt config. | Wrap critical section with `flock -n /tmp/.clash_sub_update.lock` or `$XDG_RUNTIME_DIR` equivalent. |
| Q9 | 🟡 | `script/common.sh:13-16` | CWD-relative paths | `SCRIPT_BASE_DIR='./script'`, `RESOURCES_BASE_DIR='./resources'` — assumes sourcing from repo root. Scripts sourcing `common.sh` from other directories silently get wrong paths. | Derive from `BASH_SOURCE` or add guard: `[[ -d ./script ]] \|\| { echo "Must run from repo root" >&2; exit 1; }` |
| Q10 | 🟡 | `vpn-tools/load_env.sh:41-44` | Global export pollution | `set -a; source "$env_file"; set +a` exports ALL `.env` variables into caller environment, potentially overwriting `PATH` or other critical variables. | Use a safer pattern: parse key=value lines explicitly, or prefix variables with `CLASH_`. |
| Q11 | 🟡 | `uninstall.sh` | Incomplete cleanup | Install creates `clash-subscription-refresh.service` and `.timer` in `~/.config/systemd/user/`, but uninstall only removes `mihomo.service` and `clash-proxy-env.service`. Stale timer continues running. | Add `rm -f` for `clash-subscription-refresh.{service,timer}` and `systemctl --user disable` calls. |

## ③ systemd Unit Issues

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| S1 | 🟢 | `systemd/clash-subscription-refresh.service:3` | Missing dependency | `After=default.target` but no `Wants/After=network-online.target`. Service performs network fetch and may fire before connectivity is ready. | Add `After=network-online.target` and `Wants=network-online.target`. |
| S2 | 🟢 | `systemd/clash-subscription-refresh.service` | No hardening | Missing security directives for a network-fetching unit. | Add: `NoNewPrivileges=true`, `ProtectSystem=strict`, `ReadWritePaths=%h/.local/share/clash`. |
| S3 | 🟢 | `script/update_clash_subscription.sh:50` | No URL scheme enforcement | `curl` accepts any scheme accepted by libcurl. No explicit `https://` enforcement. | Add: `[[ "$URL" =~ ^https?:// ]] \|\| { echo "Invalid URL scheme" >&2; exit 1; }` |

## Remediation Roadmap

### Priority 1 — 🔴 Critical
1. **B6+B7 — `set -e` + awk exit in test_ai_connectivity.sh**: Both break best-node selection logic. Refactor to `if awk ...; then` pattern. **Effort: 10 min.** Same fix class as the already-completed B1.
2. **Q6 — Silent mixin merge failure in clashctl.sh**: Add post-merge integrity validation instead of blind `|| true`. **Effort: 20 min.** Requires careful testing with `yq` failure scenarios.

### Priority 2 — 🟡 Warning
3. **B8 — Unquoted array in percentile()**: Use `mapfile`. **2 min.**
4. **Q8 — Config swap race**: Add `flock` to `update_clash_subscription.sh`. **5 min.**
5. **Q11 — Uninstall cleanup**: Add subscription refresh unit removal. **5 min.**
6. **Q7 — Conditional YAML validation**: Add minimal fallback check. **5 min.**
7. **Q9 — CWD-relative paths**: Add repo-root guard in `common.sh`. **5 min.**
8. **Q10 — Global env export**: Document risk or use explicit parsing. **15 min.**

### Priority 3 — 🟢 Enhancement
9. S1 network-online dep, S2 systemd hardening, S3 URL scheme guard — incremental improvements.

## Next Steps
- B6+B7 are the same fix class as the already-completed B1 — recommend immediate fix.
- Q6 (merge error handling) is the most impactful quality issue; recommend a careful fix with rollback testing.
- For Priority 1/2 items, switch to implementation mode with this report to generate a phased plan.
