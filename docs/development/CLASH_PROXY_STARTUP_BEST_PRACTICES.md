# Clash Proxy Startup Best Practices (systemd + fast shells)

This document describes a recommended way to run Clash/Mihomo as a **boot‑time user service** while keeping
`~/.bashrc` / `~/.zshrc` **lightweight and fast**, especially for VS Code terminals and short‑lived shells.

The goal:

- Clash kernel + system proxy come up automatically after login (and optionally at boot via `loginctl enable-linger`).
- All terminals see a consistent proxy environment **without running heavy logic on every shell startup**.
- Developers can still use `clash`, `clashon`, `clashoff`, etc. on demand.

This replaces the older pattern where `~/.bashrc` directly sourced `common.sh`/`clashctl.sh` and ran `watch_proxy`
(or even `clashon`) in every interactive shell.

---

## 1. What the old `.bashrc` integration did

The legacy auto‑injection (installed by `_set_rc` in `script/common.sh`) used to append a block like:

```bash
# >>> clashctl auto-start >>>
if [ -f "$CLASH_SCRIPT_DIR/common.sh" ] && [ -f "$CLASH_SCRIPT_DIR/clashctl.sh" ]; then
    . "$CLASH_SCRIPT_DIR/common.sh"
    . "$CLASH_SCRIPT_DIR/clashctl.sh"
    case "$-" in
        *i*) watch_proxy >/dev/null 2>&1 || true ;;
    esac
fi
# <<< clashctl auto-start <<<
```

Behaviour:

- Every interactive shell:
  - sourced `common.sh` and `clashctl.sh` (1k+ lines of helpers, yq wrappers, etc.);
  - immediately called `watch_proxy`, which:
    - ran `_get_proxy_port` (multiple `yq` reads against `~/.local/share/clash/runtime.yaml`),
    - queried `systemctl --user is-active …`,
    - sometimes called `clashon`, which then touched `gsettings`, `kwriteconfig5`, `git config` and APT proxy files.
- Result: `source ~/.bashrc` could easily take **hundreds of ms to seconds**, especially on cold caches or when
  systemd had to wake user services. VS Code integrated terminals often "hung" while this work completed.

The rest of a typical `~/.bashrc` is cheap (aliases, PATH, prompt), so this Clash block becomes the dominant
startup cost.

---

## 2. Target architecture

We recommend the following model:

1. **systemd user services** are responsible for:
   - starting the Clash/Mihomo kernel;
   - configuring system‑level proxy settings (GNOME `gsettings`, KDE `kwriteconfig5`, APT proxy, etc.).

2. **Shell startup** is responsible for at most:
   - cheaply exporting `http_proxy` / `HTTPS_PROXY` / `ALL_PROXY` from a small state file (no `yq`, no `systemctl`), or
   - doing nothing at all if you prefer purely system‑level proxy behaviour.

3. **On‑demand control** (e.g. `clash`, `clashon`, `clashoff`) remains available, but the heavy logic only runs
   when you explicitly call these commands, not on every new shell.

This is friendlier to IDEs (VS Code, JetBrains), SSH one‑liners, and any workflow that spawns many short‑lived shells.

---

## 3. Ensure systemd user services are doing the heavy lifting

The installer already creates two user services under `~/.config/systemd/user/`:

- `mihomo.service` **or** `clash.service` (the kernel, depending on which binary is installed);
- `clash-proxy-env.service` (one‑shot proxy environment setup).

You can verify and enable them with:

```bash
# As your normal user (no sudo needed for --user)
systemctl --user status mihomo.service clash-proxy-env.service

# If they are not enabled/started yet:
systemctl --user enable --now mihomo.service clash-proxy-env.service
```

If you want these services to keep running after logout and start at boot for this user, enable lingering:

```bash
# May require sudo depending on distro policy
loginctl enable-linger "$USER"
```

With this in place:

- the kernel starts once per login (or boot, with lingering);
- `clash-proxy-env.service` runs `_set_system_proxy` once, which:
  - updates GNOME/KDE proxy settings;
  - writes APT proxy snippet under `/tmp/95clash-proxy` (to be copied to `/etc/apt/apt.conf.d/` if desired);
  - records the chosen mixed port and authentication into `/tmp/.clash_system_proxy_state`.

> **Note**: Environment variables set inside the systemd unit do **not** automatically propagate to interactive
> shells. That is why we rely on a small state file for shells to read from, instead of re‑running the whole
> `_set_system_proxy` pipeline per shell.

---

## 4. Remove heavy auto‑start from `~/.bashrc` / `~/.zshrc`

To avoid running `watch_proxy` and systemd/yq work on every shell, you should **remove** the injected
`clashctl auto-start` block from your shell RC files.

### 4.1 Manual edit

Open `~/.bashrc` (and `~/.zshrc` if applicable), locate the block between the markers and delete it:

```bash
# >>> clashctl auto-start >>>
... anything in here ...
# <<< clashctl auto-start <<<
```

Save the file. New shells will no longer source Clash helpers or run `watch_proxy` automatically.

### 4.2 Using the helper (optional)

If you prefer to let the script clean things up for you, from a shell run:

```bash
# This sources the installed helpers and calls the RC cleanup function once
source "$HOME/.local/share/clash/script/common.sh"
_set_rc unset
```

This removes the auto‑start block from `~/.bashrc` and `~/.zshrc`, and deletes the fish RC snippet if present.

---

## 5. Lightweight proxy environment for shells

Once systemd user services are managing the kernel and system‑wide proxy settings, you can let shells pick up the
current mixed port by reading the state file that `_set_system_proxy` maintains:

- Path: `/tmp/.clash_system_proxy_state`
- Format: `MIXED_PORT|AUTH`, where `AUTH` is either empty or something like `user:pass@`.

Add this small, **pure‑shell** snippet to the end of your `~/.bashrc` and/or `~/.zshrc`:

```bash
# >>> clash proxy env (lightweight) >>>
STATE_FILE="/tmp/.clash_system_proxy_state"
if [ -f "$STATE_FILE" ]; then
    IFS='|' read -r MIXED_PORT AUTH_PREFIX <"$STATE_FILE" 2>/dev/null || MIXED_PORT=""
    # Basic numeric guard; avoid accidental injection of garbage into proxy URLs
    case "$MIXED_PORT" in
        ''|*[!0-9]*) : ;;  # non-numeric or empty; skip
        *)
            if [ "$MIXED_PORT" -ge 1 ] 2>/dev/null; then
                # AUTH_PREFIX already includes trailing '@' when auth is configured, or is empty otherwise
                export http_proxy="http://${AUTH_PREFIX}127.0.0.1:${MIXED_PORT}"
                export https_proxy="$http_proxy"
                export HTTP_PROXY="$http_proxy"
                export HTTPS_PROXY="$http_proxy"
                export all_proxy="socks5h://${AUTH_PREFIX}127.0.0.1:${MIXED_PORT}"
                export ALL_PROXY="$all_proxy"
                # Keep no_proxy simple and fast; systemd/GNOME rules still apply separately
                export no_proxy="localhost,127.0.0.1,::1,0.0.0.0,*.local,.localhost,.local"
                export NO_PROXY="$no_proxy"
            fi
            ;;
    esac
fi
# <<< clash proxy env (lightweight) <<<
```

Characteristics:

- Only performs a single small file read and a couple of `export` statements.
- Does **not** run `yq`, `systemctl`, `gsettings`, or any network calls.
- If the Clash service is stopped, `_unset_system_proxy` removes the state file, so new shells simply skip the block.

This gives you a fast startup path that still honours the dynamic mixed port chosen by Clash.

---

## 6. Optional: lazy‑load Clash CLI helpers

If you still want `clash`, `clashon`, `clashoff`, etc. available in every shell without paying the cost of sourcing
all helper scripts up front, you can use **lazy stubs**:

```bash
# >>> clashctl lazy stubs >>>
CLASH_SCRIPT_DIR="$HOME/.local/share/clash/script"

_clashctl_lazy_bootstrap() {
    # Load helpers only once per shell
    unset -f clash clashctl mihomo mihomoctl _clashctl_lazy_bootstrap
    [ -f "$CLASH_SCRIPT_DIR/common.sh" ] && . "$CLASH_SCRIPT_DIR/common.sh"
    [ -f "$CLASH_SCRIPT_DIR/clashctl.sh" ] && . "$CLASH_SCRIPT_DIR/clashctl.sh"
}

clash()      { _clashctl_lazy_bootstrap; clash      "$@"; }
clashctl()   { _clashctl_lazy_bootstrap; clashctl   "$@"; }
mihomo()     { _clashctl_lazy_bootstrap; mihomo     "$@"; }
mihomoctl()  { _clashctl_lazy_bootstrap; mihomoctl  "$@"; }
# <<< clashctl lazy stubs >>>
```

Now:

- Shell startup only defines a few tiny wrapper functions.
- The first time you call `clash`/`clashctl`/`mihomo` in that shell, the wrappers source `common.sh`/
  `clashctl.sh`, replace themselves with the real implementations, and then forward your original command.
- Subsequent calls in the same shell pay no extra overhead.

This pattern is especially helpful in VS Code, where you might not run any Clash commands from the integrated
terminal but still want them available when needed.

---

## 7. Summary

- Let **systemd user services** (`mihomo.service`, `clash-proxy-env.service`) handle kernel startup and system‑level
  proxy configuration at login/boot.
- Keep `~/.bashrc` / `~/.zshrc` **cheap**:
  - remove the heavy `clashctl auto-start` block that runs `watch_proxy` on every shell;
  - optionally add a small snippet that reads `/tmp/.clash_system_proxy_state` and exports proxy variables;
  - optionally add lazy stubs for `clash`/`clashctl` so helpers load only when used.

With this setup, you get:

- fast, responsive terminals and IDE shells;
- a single source of truth (systemd user services) for Clash lifecycle;
- minimal per‑shell overhead while preserving convenient control commands.
