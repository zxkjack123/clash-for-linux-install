#!/usr/bin/env bash
# shellcheck disable=SC1091
. script/common.sh
. script/clashctl.sh

type _valid_env >/dev/null 2>&1 || { echo "ERROR: must run from repository root (missing script/common.sh or failed to source)" >&2; exit 2; }

_valid_env

clashoff >&/dev/null

# Stop and disable user systemd services
systemctl --user stop "$BIN_KERNEL_NAME" >&/dev/null
systemctl --user disable "$BIN_KERNEL_NAME" >&/dev/null
systemctl --user stop clash-proxy-env.service >&/dev/null
systemctl --user disable clash-proxy-env.service >&/dev/null
rm -f "${USER_HOME}/.config/systemd/user/${BIN_KERNEL_NAME}.service"
rm -f "${USER_HOME}/.config/systemd/user/clash-proxy-env.service"
systemctl --user daemon-reload

# Disable lingering if it was enabled
loginctl disable-linger "$USER" 2>/dev/null || true

# Safety guard: never allow uninstall to delete an unexpected path.
# Expected default: $HOME/.local/share/clash
if [ -z "${CLASH_BASE_DIR:-}" ]; then
	_failcat "卸载失败：CLASH_BASE_DIR 为空，拒绝执行 rm -rf" >&2
	exit 1
fi
if [ "$CLASH_BASE_DIR" = "/" ] || [ "$CLASH_BASE_DIR" = "$USER_HOME" ] || [ "$CLASH_BASE_DIR" = "$HOME" ]; then
	_failcat "卸载失败：CLASH_BASE_DIR=$CLASH_BASE_DIR 看起来不安全，拒绝执行 rm -rf" >&2
	exit 1
fi
case "$CLASH_BASE_DIR" in
	"$USER_HOME"/*) : ;;
	*)
		_failcat "卸载失败：CLASH_BASE_DIR=$CLASH_BASE_DIR 不在 $USER_HOME 下，拒绝执行 rm -rf" >&2
		exit 1
		;;
esac

rm -rf "$CLASH_BASE_DIR"
# Remove CLI entrypoints if they are symlinks
for _cmd in clashctl mihomoctl; do
	_dest="${USER_HOME}/.local/bin/${_cmd}"
	[ -L "$_dest" ] && rm -f "$_dest" 2>/dev/null || true
done
# Remove user crontab entries if they exist
[ -f "$CLASH_CRON_TAB" ] && sed -i '/clashupdate/d' "$CLASH_CRON_TAB" >&/dev/null
_set_rc unset

_okcat '✨' '已卸载，相关配置已清除'
_quit
