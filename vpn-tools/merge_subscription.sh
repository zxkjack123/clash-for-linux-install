#!/usr/bin/env bash
# merge_subscription.sh (minimal clean version) - 仅合并/对比 proxies, 可选自动追加到分组。
set -euo pipefail

CURRENT="resources/config.yaml"
NEW_FILE=""
SUB_URL=""
OUTPUT=""
APPLY=0
AUTO_APPEND=0
GROUPS="GLOBAL,自动选择,故障转移"

log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
fail(){ log "ERROR: $*"; exit 3; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--current) CURRENT="$2"; shift 2 ;;
		--new) NEW_FILE="$2"; shift 2 ;;
		--url) SUB_URL="$2"; shift 2 ;;
		--output) OUTPUT="$2"; shift 2 ;;
		--apply) APPLY=1; shift ;;
		--auto-append-new) AUTO_APPEND=1; shift ;;
		--groups) GROUPS="$2"; shift 2 ;;
		-h|--help) grep -E '^# ' "$0" | sed 's/^# \?//'; exit 0 ;;
		*) fail "未知参数: $1" ;;
	esac
done

[[ -f "$CURRENT" ]] || fail "当前配置不存在: $CURRENT"
TMP_DIR=$(mktemp -d -t merge_sub_clean.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$SUB_URL" ]]; then
	command -v curl >/dev/null 2>&1 || fail "需要 curl"
	NEW_FILE="$TMP_DIR/sub.yaml"
	safe_url=$(printf '%s' "$SUB_URL" | sed -E 's#^(https?://)[^/@]+@#\1***@#' | sed -E 's/([?&](token|access_token|apikey|api_key|key|secret)=)[^&#]*/\1***/gI')
	log "下载订阅: $safe_url"
	curl -fsSL --retry 2 --connect-timeout 8 --max-time 30 "$SUB_URL" -o "$NEW_FILE" || fail "下载失败"
fi

[[ -n "$NEW_FILE" && -f "$NEW_FILE" ]] || fail "未提供新订阅文件"

OLD_P="$TMP_DIR/old.yaml"
NEW_P="$TMP_DIR/new.yaml"

extract(){
	awk '/^proxies:/{f=1;print;next} /^[A-Za-z0-9_-]+:/{if(f)exit} f{print}' "$1" > "$2"
	grep -q '^proxies:' "$2" || fail "缺少 proxies 段: $1"
}

extract "$CURRENT" "$OLD_P"
extract "$NEW_FILE" "$NEW_P"

mkmap(){
	local src="$1" out="$2"
	: > "$out"
	(grep -E '^[[:space:]]*-[[:space:]]*\{' "$src" 2>/dev/null || true) | while IFS= read -r l; do
		b=${l#*- \{}
		b=${b%}*}
		name=""; server=""; port=""
		IFS=',' read -r -a parts <<< "$b"
		for kv in "${parts[@]}"; do
			k=${kv%%:*}; v=${kv#*:}
			k=$(echo "$k" | sed "s/^['\"[:space:]]*//;s/['\"[:space:]]*$//")
			v=$(echo "$v" | sed "s/^['\"[:space:]]*//;s/['\"[:space:]]*$//")
			case "$k" in
				name) name="$v" ;;
				server) server="$v" ;;
				port) port="$v" ;;
			esac
		done
		[[ -n "$name" ]] && printf '%s\t%s:%s\n' "$name" "$server" "$port" >> "$out"
	done
}

OLD_M="$TMP_DIR/old.map"
NEW_M="$TMP_DIR/new.map"
mkmap "$OLD_P" "$OLD_M"
mkmap "$NEW_P" "$NEW_M"

declare -A OLD NEW ADD DEL CHG
while IFS=$'\t' read -r n s; do [[ -n ${n:-} ]] && OLD[$n]="$s"; done < "$OLD_M"
while IFS=$'\t' read -r n s; do [[ -n ${n:-} ]] && NEW[$n]="$s"; done < "$NEW_M"

for n in "${!OLD[@]}"; do
	if [[ -z ${NEW[$n]:-} ]]; then
		DEL[$n]=1
	elif [[ ${OLD[$n]} != ${NEW[$n]} ]]; then
		CHG[$n]=1
	fi
done
for n in "${!NEW[@]}"; do
	[[ -n ${OLD[$n]:-} ]] || ADD[$n]=1
done

log "Diff: 新增=${#ADD[@]} 删除=${#DEL[@]} 变更=${#CHG[@]}"
if (( ${#ADD[@]} )); then echo '  新增:' >&2; for n in "${!ADD[@]}"; do echo "    - $n"; done | sort >&2; fi
if (( ${#DEL[@]} )); then echo '  删除:' >&2; for n in "${!DEL[@]}"; do echo "    - $n"; done | sort >&2; fi
if (( ${#CHG[@]} )); then echo '  变更:' >&2; for n in "${!CHG[@]}"; do echo "    - $n: ${OLD[$n]} -> ${NEW[$n]}"; done | sort >&2; fi

MERGED="$TMP_DIR/merged.yaml"
awk -v nf="$NEW_P" 'BEGIN{while((getline l<nf)>0)buf[++i]=l} /^proxies:/{sw=1;for(j=1;j<=i;j++)print buf[j];next} /^[A-Za-z0-9_-]+:/{if(sw)sw=0} sw{next} {print}' "$CURRENT" > "$MERGED"
[[ -s "$MERGED" ]] || fail "合并结果为空"

if [[ $AUTO_APPEND -eq 1 && ${#ADD[@]} -gt 0 ]]; then
	IFS=',' read -r -a GS <<< "$GROUPS"
	TMP2="$TMP_DIR/appd.yaml"
	:>"$TMP2"
	while IFS= read -r line; do
		for g in "${GS[@]}"; do
			if [[ $line =~ name:[[:space:]]*$g[^,]*,.*proxies:.*\[.*\] ]]; then
				inner=${line#*\[}; inner=${inner%]*}
				declare -A CUR=()
				IFS=',' read -r -a arr <<< "$inner"
				for r in "${arr[@]}"; do
					r=$(echo "$r" | sed "s/^['\"[:space:]]*//;s/['\"[:space:]]*$//")
					[[ -n "$r" ]] && CUR[$r]=1
				done
				for n in "${!ADD[@]}"; do
					[[ ${CUR[$n]:-} ]] || inner="$inner, $n"
				done
				inner=$(echo "$inner" | sed 's/, */, /g')
				line="${line%%\[*}[$inner] }"
				break
			fi
		done
		echo "$line" >> "$TMP2"
	done < "$MERGED"
	mv "$TMP2" "$MERGED"
	log "已追加新增节点"
fi

declare -A NEWSET
for n in "${!NEW[@]}"; do NEWSET[$n]=1; done
MISS="$TMP_DIR/miss.txt"
:>"$MISS"
while IFS= read -r line; do
	[[ $line =~ proxies:.*\[.*\] ]] || continue
	inner=${line#*\[}; inner=${inner%]*}
	IFS=',' read -r -a arr <<< "$inner"
	for r in "${arr[@]}"; do
		r=$(echo "$r" | sed "s/^['\"[:space:]]*//;s/['\"[:space:]]*$//")
		[[ -z "$r" ]] && continue
		[[ ${NEWSET[$r]:-} ]] || echo "$r" >> "$MISS"
	done
done < "$MERGED"

if [[ -s "$MISS" ]]; then
	log "缺失引用:"
	sort -u "$MISS" | sed 's/^/  - /'
else
	log "未发现缺失引用"
fi

if [[ $APPLY -eq 1 ]]; then
	mkdir -p resources/backup
	BK="resources/backup/config_$(date +%Y%m%d_%H%M%S).yaml"
	cp "$CURRENT" "$BK"
	cp "$MERGED" "$CURRENT"
	log "已应用 (备份: $BK)"
	if [[ -n "$OUTPUT" ]]; then
		cp "$MERGED" "$OUTPUT"
		log "写入 $OUTPUT"
	fi
else
	if [[ -n "$OUTPUT" ]]; then
		cp "$MERGED" "$OUTPUT"
		log "写入 $OUTPUT (未覆盖)"
	else
		log "--- 合并预览 ---"
		cat "$MERGED"
	fi
	log "使用 --apply 应用修改"
fi

exit 0
