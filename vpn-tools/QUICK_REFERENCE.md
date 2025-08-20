# VPN Tools Quick Reference

Fast cheat‑sheet for the diagnostic / optimization scripts. All scripts assume:
	* Controller: http://127.0.0.1:9090 (override: CLASH_API)
	* HTTP Proxy: http://127.0.0.1:7890 (override: PROXY)
	* Default AI group name: AI (override with --group)

## Core Status & Overview
| Command | Purpose | Duration |
|---------|---------|----------|
| ./show_vpn_status.sh | One‑shot controller + key endpoint probes + exit IP | 2–5s |
| ./quick_vpn_check.sh | Lightweight multi-endpoint health score | 8–15s |
| ./proxy_connectivity_report.sh | Markdown connectivity grading report | 20–40s |

## AI Connectivity & Optimization
| Command | Purpose | Duration |
|---------|---------|----------|
| ./quick_ai_test.sh | Smoke test OpenAI/ChatGPT/Claude/Braintrust | 6–12s |
| ./optimize_ai.sh | Score AI nodes (few endpoints) & optionally apply | 15–30s |
| ./optimize_ai_enhanced.sh | Deeper AI scoring (advanced) | 1–3m |
| ./test_ai_simple.sh | Iterate all AI nodes (basic metrics, no apply) | 1–2m |
| ./test_ai_connectivity.sh --rounds 5 --apply | Comprehensive multi‑round stability & selection | 8–15m |
| ./test_ai_nodes.sh | Targeted AI node list test (existing) | varies |
| ./customize_ai_group.sh | Interactive manual AI node selection | user driven |

Useful switches:
	--group NAME   Use alternate proxy group
	--rounds N     Number of rounds (stability scripts)
	--limit N      Limit number of nodes evaluated
	--apply        Apply best node to group
	--json file    Write machine‑readable metrics
	--md file      Write markdown summary

## Streaming / YouTube
| Command | Purpose | Duration |
|---------|---------|----------|
| ./quick_streaming_test.sh | Smoke test YouTube + Netflix endpoints | 6–12s |
| ./select_youtube_node.sh | Basic YouTube node selection | 15–30s |
| ./optimize_youtube_streaming.sh --apply | Comprehensive YT stability + selection | 1–2m |
| ./streaming_manager.sh | Interactive streaming node manager | user driven |

## Network Diagnostics
| Command | Purpose | Duration |
|---------|---------|----------|
| ./network_connectivity_test.sh quick | Direct vs proxy latency/DNS quick view | 10–20s |
| ./network_connectivity_test.sh full | Extended endpoint latency + DNS checks | 40–90s |
| ./network_change_probe.sh | Correlate network change events & log churn | bg/continuous |
| ./system_network_audit.sh | Point-in-time audit: routes, DNS, proxy env | 4–8s |
| ./quick_vpn_check.sh | General proxy health (also in status) | 8–15s |
| ./run_batch_diagnostics.sh | Batch run key quick diagnostics & summarize | 20–40s |

## Specialized / Regional / Misc
| Command | Purpose |
|---------|---------|
| ./test_chinese_ai_platforms.sh | Regional AI platforms reachability |
| ./quick_openxlab_access.sh | OpenXLab quick access test |
| ./fix_openxlab_connectivity.sh | Attempt to remediate OpenXLab issues |
| ./test_braintrust_connectivity.sh | Braintrust connectivity deep test |
| ./test_docker_proxy.sh | Docker traffic proxy verification |
| ./launcher.sh | Unified interactive menu for categories |
| ./show_help.sh | Extended help / catalog |
| ./merge_subscription.sh | Merge new subscription & (optional) screen slow nodes |

## Typical Workflows
1. Quick health: ./show_vpn_status.sh then ./quick_ai_test.sh
2. Need better AI latency: ./optimize_ai.sh --apply
3. Full AI stability session: ./test_ai_connectivity.sh --rounds 5 --apply --json ai.json --md ai.md
4. YouTube buffering: ./optimize_youtube_streaming.sh --apply
5. Investigate sporadic failures: ./network_connectivity_test.sh full && ./proxy_connectivity_report.sh
6. Detect network change bursts: ./network_change_probe.sh (background) then review log
7. Cleanup slow nodes on subscription merge: ./merge_subscription.sh --url <SUB> --screen-timeout drop --timeout-threshold 1800 --apply

## Environment Variables
| Var | Meaning | Default |
|-----|---------|---------|
| CLASH_API | Controller base URL | http://127.0.0.1:9090 |
| PROXY | HTTP proxy URL | http://127.0.0.1:7890 |

## Exit Codes (General Convention)
0 success / results produced
1 controller or critical dependency unreachable
2 invalid usage / arguments
>2 script-specific error (documented inline)

## Tips
* For large node groups, use --limit to sample before full test.
* JSON output pairs well with jq for dashboards.
* Run heavy tests during low-traffic periods to avoid skew from other bandwidth usage.
* Subscription merge slow node screening:
	- Tag slow nodes:  ./merge_subscription.sh --new sub.yaml --screen-timeout tag --timeout-threshold 1500
	- Drop slow nodes: ./merge_subscription.sh --url <SUB_URL> --screen-timeout drop --timeout-threshold 1800 --apply
	- Threshold unit is ms (TCP connect time using /dev/tcp). Failures count as slow.

