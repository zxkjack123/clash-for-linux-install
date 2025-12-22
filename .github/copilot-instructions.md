# GitHub Copilot Instructions (Repository)

These instructions apply to GitHub Copilot (Chat/Edits/Agent) when working in this repository.

## Project context

- This repo manages **Clash/Mihomo** setup on Linux (scripts, systemd units, mixin/config merge, diagnostics, VPN testing tools).
- Most changes are **shell scripts** (`bash`) and YAML configs.
- Key goals: **stability**, **idempotency**, **safe defaults**, and **clear diagnostics**.

## Safety & security (must follow)

- **Never print or commit secrets**:
  - controller `secret`, subscription URLs/tokens, API keys.
  - When showing URLs, always redact query parameters like `token`, `apikey`, `key`, `secret`.
- Prefer **localhost-only** controller exposure unless explicitly requested.
- Any tool interacting with the controller must support **Authorization header** when `secret` is set.

## Coding style (shell)

- Use `set -euo pipefail` for new scripts unless a script is explicitly a diagnostic that must continue on error.
- Avoid interactive prompts in automation paths; use clear exit codes and messages.
- Add timeouts to all network calls (`curl --connect-timeout ... --max-time ...`).
- Keep changes minimal, avoid unrelated reformatting.

## Proxy / networking behavior

- Assume a local proxy is available at `http://127.0.0.1:7890`.
- Prefer **evidence-based** debugging:
  - When asked “did traffic go through mihomo?”, use controller `/connections` tracing (see repo tools section below).

## Web fetching policy (important)

### 1) Don’t fight anti-bot systems

If a site is protected by anti-automation (Cloudflare/PerimeterX/Akamai, etc.), Copilot should:

- **Do not attempt** to bypass challenges, emulate a full browser fingerprint, or evade access controls.
- Detect common signs quickly (example signals):
  - `cf-mitigated: challenge`, `server: cloudflare`
  - HTTP `403/429` with challenge pages or large HTML that isn’t the real article.

### 2) Prefer “bring the content to the workspace”

For websites likely to block fetch (common academic publishers):

- `sciencedirect.com` (Elsevier)
- `link.springer.com`
- `ieeexplore.ieee.org`
- `dl.acm.org`
- `onlinelibrary.wiley.com`
- `nature.com` / `springernature.com`

Do this instead:

- Ask the user to provide one of:
  - the PDF, exported HTML, or copied text excerpt
  - DOI / abstract page that is publicly accessible
  - institution-allowed TDM/API output (if available)
- Then summarize/analyze from the **local artifact**.

### 3) Avoid long “Fetching …” hangs

When a fetch is likely to hang:

- Prefer short, bounded checks:
  - `curl -I -L` or a small `GET` with strict timeouts
- If challenge/blocked is detected, stop early and propose the local-PDF workflow.

## Repo tools you should use (when relevant)

- `vpn-tools/optimize_vscode_copilot.sh`
  - Validates GitHub/Copilot/OpenAI endpoints via proxy.
- `vpn-tools/trace_mihomo_connections.sh`
  - Live-traces mihomo controller `/connections` to prove rule + chain (DIRECT vs proxy groups).
- `script/clash_diagnose.sh --fast --json`
  - Fast health snapshot; should not false-alarm when controller `secret` is enabled.

## Communication expectations

- When diagnosing network issues, always report:
  - whether the request went through mihomo (rule + chain)
  - whether failure is **connectivity** vs **server-side challenge/block**
  - a minimal, actionable mitigation path
