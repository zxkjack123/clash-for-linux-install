# VPN Testing Tools Guide

This guide provides detailed explanations, metrics definitions, and operational
philosophy for the restored VPN diagnostic & optimization scripts under
`vpn-tools/`.

## Design Principles
1. Fast First Insight: Provide a sub‑15 second path (quick scripts) to detect gross failures.
2. Progressive Depth: Heavier scripts add rounds, percentiles, stability metrics only when needed.
3. Safety: Write operations limited to group node switching when explicitly requested (`--apply`). No destructive config edits.
4. Portability: Pure POSIX shell where feasible; optional jq for richer JSON output.
5. Deterministic Scoring: Weighted composite scores documented inside each script header.

## Common Environment
Environment variables you may override:
| Var | Meaning | Default |
|-----|---------|---------|
| CLASH_API | Clash/Mihomo external controller | http://127.0.0.1:9090 |
| PROXY | HTTP proxy URL for tests | http://127.0.0.1:7890 |

All scripts assume the proxy is working locally; direct vs proxy comparisons appear in `network_connectivity_test.sh`.

## Metrics Glossary
| Metric | Definition |
|--------|-----------|
| success_ratio | successes / attempts across endpoints per node |
| latency_med | 50th percentile (median) successful request time_total |
| latency_p95 | 95th percentile latency for tail performance |
| jitter | Standard deviation of successful request latencies |
| score | Composite weighting of success, latency, stability (details inline) |
| rounds | Rounds completed (may be fewer due to early abort) |
| errors | Aggregated non‑success HTTP codes (or timeout) counts |

## Script Deep Dives

### show_vpn_status.sh
Snapshot view: controller version, current selected nodes for key groups (AI, YOUTUBE), quick probes (OpenAI, YouTube, Netflix), exit IP geolocation. Use this before deeper tests to ensure baseline availability.

### quick_vpn_check.sh
Rapid multi-endpoint (GitHub API, OpenAI auth probe, YouTube, Cloudflare trace, controller auth) scoring. Emits textual or JSON summary.
Updates (Aug 2025):
* Fixed premature exit (regex + set -e interaction) and cleaned debug noise.
* Introduced AUTH classification (401/403 treated reachable) separate from FAIL.
* Dynamic max_score when optional SOCKS port absent (skip instead of penalize).
Scoring: Each successful component adds to score; percentage = earned / possible.

### quick_ai_test.sh
Targets core AI endpoints to confirm reachability. Provides success counts and basic latency; no node switching.

### optimize_ai.sh / optimize_ai_enhanced.sh
Both perform node scoring for AI usage; enhanced variant uses more endpoints and possibly parallel probing (if configured). Standard version favors speed (under 30s). Result: best node optionally applied with `--apply`.

### test_ai_simple.sh
Iterates all nodes, one pass per endpoint set, no multi-round stability. Useful for a broad first scan across large groups.

### test_ai_connectivity.sh (Comprehensive)
Multi-round methodology:
1. Each round shuffles a fixed endpoint list to reduce ordering bias.
2. Early abort after round 2 if success_ratio < 0.30, conserving total runtime.
3. Collects latency vectors for percentile & jitter computation.
4. Composite Score = Success (60%) + Latency (30%) + Stability (10%). Latency sub-score blends median (60%) and P95 (40%). Jitter currently omitted (future reintroduction planned).
5. Emits aligned table; pipe to `sort -k<SCORE_COL> -nr` for ranking. Optional `--json file` & `--md file` for artifacts.
6. Layered secret autodetect: environment > mixin.yaml > runtime.yaml.

### customize_ai_group.sh
Interactive fuzzy filter + quick latency test to let an operator manually choose nodes. Does not auto-rank beyond displayed metrics.

### optimize_youtube_streaming.sh / select_youtube_node.sh
Focus on YouTube streaming readiness. The comprehensive script adds stability weighting (latency variance, repeated pixel endpoints) to avoid selecting bursty nodes.

### quick_streaming_test.sh
Simple streaming smoke set (YouTube, Netflix static). Highlights immediate geolocation or blocking issues.

### streaming_manager.sh
Interactive wrapper presenting quick probing, node switch operations, and verification loops.

### network_connectivity_test.sh
Two modes:
* quick: limited endpoints, direct vs proxy delta and DNS resolution timing.
* full: extended endpoint matrix, DNS comparisons, optional traceroute (if tool available and privileges allow).

### proxy_connectivity_report.sh
Generates Markdown with latency grading (A/B/C/D) based on threshold tiers and simple color-coded style (if rendered). Ideal for attachments in issue diagnostics.

## Scoring Philosophy
Priority order: Availability > Predictable Latency > Peak Speed. Therefore success_ratio dominates scoring. P95 keeps tail latency in check and jitter disfavors unstable nodes.

## JSON Output Consumption
Example pipeline:
```
./test_ai_connectivity.sh --rounds 5 --json ai.json --limit 10
jq -r '.nodes[] | "\(.name),\(.score),\(.success_ratio)"' ai.json | sort -t',' -k2 -nr | column -s, -t
```

## Performance Considerations
* Reduce ROUNDS for quicker (less stable) assessments.
* Use --limit to sample top N nodes then rerun full test for finalists.
* Avoid running heavy tests concurrently; saturation may skew latency.

## Troubleshooting
| Symptom | Possible Cause | Mitigation |
|---------|----------------|-----------|
| All nodes low success_ratio | Upstream API blocking / global outage | Verify endpoints manually with curl + different network |
| High jitter on best latency node | Route instability / congestion | Re-run test; consider alternate region |
| Scripts fail: controller unreachable | Clash/Mihomo service down or port changed | Check systemd unit, confirm external-controller port |
| jq not found warnings | jq not installed | Install jq for richer JSON: `sudo apt install jq` |

## Extending the Toolkit
1. Add new endpoint: choose representative, stable, low-side-effect URL returning 200/204.
2. Add to arrays inside target scripts; ensure timeouts <= 12s to keep overall runtime bounded.
3. Adjust scoring weights only with rationale; keep success dominant.

## Safety & Rate Limits
Endpoints selected are lightweight metadata/health URLs. Avoid adding heavy model inference or streaming downloads to prevent quota exhaustion or ToS violations.

## Changelog Notes
Restoration batch reimplemented previously truncated scripts (Aug 2025). This guide documents their intended behavior for future recovery.

## Future Enhancements (Ideas)
* Parallel probing (bounded concurrency) where determinism not required.
* Shared shell lib for curl_probe, percentile, scoring helpers (reduce duplication).
* Historical trend logging (append JSON metrics + timestamp into a timeseries directory).
* HTML dashboard generation (convert JSON -> charts with a lightweight templater).
* Reintroduce jitter with smoothing / EWMA to reduce noise sensitivity.
* Integrate subscription slow-node screening (merge_subscription.sh --screen-timeout tag|drop) into skip lists for long tests.

---
Maintainer: (auto-reconstructed). Improve as you iterate—document changes here.

