# Research / Academic / Dev Routing Profile

This repo now includes a **minimal, JP-only** routing template aimed at:

- VS Code Copilot / GitHub development
- Docker / OCI registries (Docker Hub, GHCR)
- Google Scholar + common academic publishers

It is designed for the "single self-hosted JP egress" architecture (e.g. Tailscale → Tinyproxy), and avoids any streaming-oriented rule bloat.

## What you get

### Proxy groups (observable, easy to switch)

The profile introduces these groups:

- `PROXY`: main upstream (JP-only)
- `DEV`: GitHub / dev traffic
- `COPILOT`: Copilot domains (kept **above** broad GitHub rules)
- `DOCKER`: Docker/OCI registries
- `ACADEMIC`: Scholar + publishers
- `Proxy`: a backward-compatible alias for older rules/tools

All groups still point to the same JP-only upstream by default; the main benefit is **clearer routing and easier debugging**.

### Rule strategy

- Put **Copilot** and **Scholar** rules early so they don't get swallowed by broad `github.com` / `google.com` suffix rules.
- Keep **tailnet (100.64.0.0/10)** traffic `DIRECT` to reduce proxy-loop risk when system proxy is enabled.
- Keep a conservative default: `MATCH,DIRECT`.

### Known limitations (site-side restrictions)

- `scholar.google.com` may return **403** for CLI fetchers (`curl`, simple HTTP fetch, some “reader mode” tools).
	This is typically **Google anti-bot / risk control**, not a proxy failure.
- For publisher platforms (Elsevier / Springer / IEEE / ACM / Wiley / Nature), automated fetch may hit login/challenge pages.
	When that happens, prefer: PDF export, institution TDM/API output, or paste the abstract/text excerpt into your workflow.

## How to enable

This personal setup keeps routing rules **directly** in `resources/config.yaml`.

The installer uses `resources/config.yaml` as the default base config.

- This file is already updated with the research/dev groups + rules.
- Keep only your JP node in `proxies:` (the template uses `JP-Tailscale`).

## Controller secret (recommended)

Keep controller bound to localhost, and set a secret:

- `clashctl secret init`

This will:

- generate a random secret
- write it into `mixin.yaml`
- store it in `~/.local/share/clash/controller.secret`
- restart the kernel

The secret is **not printed** to the terminal.

## Related docs

- `docs/integrations/VSCODE_COPILOT_FIX.md`
- `docs/integrations/DOCKER_INTEGRATION.md`
