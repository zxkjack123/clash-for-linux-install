#!/usr/bin/env bash
# merge_subscription.sh
# 目的: 自动把新的订阅 config (只使用其 proxies 块) 合并进现有本地配置，保留你手工修改的 proxy-groups 与 rules。
# 额外: 可检测 proxy-groups 中引用的节点是否在新列表里，提示缺失；可选择把新出现的节点追加进主要分组。
#
# 用法:
#   ./merge_subscription.sh --url <SUB_URL>
#   ./merge_subscription.sh --new new_sub.yaml            # 已手动下载
#   可选参数:
#     --current resources/config.yaml  (默认)
#     --output merged.yaml             (默认: 输出到 stdout；配合 --apply 覆盖 current)
#     --apply                          (直接覆盖 current 并备份)
#     --auto-append-new                (将新订阅里新增节点追加到指定分组)
#     --groups '西瓜加速,自动选择,故障转移'  (需要追加的分组, 逗号分隔)
#     --backup-dir resources/backup    (备份目录)
#     --keep-temp                      (保留临时文件)
#     --screen-timeout tag|drop        (在合并前对新订阅节点并发探测, 高延迟节点加标签或剔除)
#     --timeout-threshold <ms>         (高延迟判定阈值, 默认 1500ms)
#     --slow-suffix "[SLOW]"           (tag 模式追加的名称后缀, 默认 [SLOW])
#     --connect-timeout <sec>           (单次 TCP 连接超时时间, 默认 3 秒)
#     --help
#
# 退出码: 0 成功; 1 参数错误; 2 下载/读取失败; 3 合并失败
# 依赖: bash>=4, curl (若使用 --url), awk, sed, diff (可选), iconv (可选)

set -euo pipefail
shopt -s extglob

CURRENT="resources/config.yaml"
NEW_FILE=""
SUB_URL=""
OUTPUT=""
APPLY=0
AUTO_APPEND=0
GROUPS="西瓜加速,自动选择,故障转移"
BACKUP_DIR="resources/backup"
KEEP_TEMP=0

# 高延迟节点筛选相关参数 (可选)
SCREEN_TIMEOUT_MODE=""   # tag | drop
TIMEOUT_THRESHOLD_MS=1500 # 判定高延迟的阈值 (毫秒)
HIGH_TIMEOUT_SUFFIX="[SLOW]" # tag 模式时追加的后缀
PROBE_CONNECT_TIMEOUT=3   # 单次 TCP 连接最大秒数 (timeout 命令)

# 百分号解码函数 (仅用于短文本 name)
decode_percent(){
  local in="$1"
  # 将 %XX 变为 \xXX 再用 printf '%b' 还原
  printf '%b' "$(echo -n "$in" | sed -E 's/%([0-9A-Fa-f]{2})/\\x\1/g')" 2>/dev/null || printf '%s' "$1"
}

# 去除 emoji (删除 4 字节 UTF-8 序列) + 去除控制字符
strip_emoji(){
  # 优先用 perl 删 emoji (更健壮), 否则回退简单 4 字节序列过滤
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CS -pe 's/[\x{1F000}-\x{1FFFF}]//g'
  else
    LC_ALL=C sed -E $'s/[\xF0-\xF7][\x80-\xBF]{3}//g' <<<"$1" 2>/dev/null || printf '%s' "$1"
  fi
}

# 规范化名称: 解码 -> 去 emoji -> 去首尾空白 -> 只保留 常见中英文数字及常用符号
sanitize_name(){
  local raw="$1"; local fallback="$2"
  local dec="$(decode_percent "$raw" 2>/dev/null || printf '%s' "$raw")"
  local noemj="$(strip_emoji "$dec")"
  # 去除控制字符
  local cleaned="$(printf '%s' "$noemj" | tr -d '\r' | tr '\n' ' ' | tr -d '\000-\010\013\014\016-\037')"
  # 删除 \xHH 形式
  cleaned="$(printf '%s' "$cleaned" | sed -E 's/\\x[0-9A-Fa-f]{2}//g' 2>/dev/null || printf '%s' "$cleaned")"
  # 非允许字符替换为空格 (保留中英文、数字、常用符号)
  cleaned="$(printf '%s' "$cleaned" | sed -E "s/[^0-9A-Za-z一-龥ぁ-んァ-ヶー·._:： -]+/ /g" 2>/dev/null || printf '%s' "$cleaned")"
  # 压缩空格
  cleaned="$(printf '%s' "$cleaned" | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//' 2>/dev/null || printf '%s' "$cleaned")"
  [[ -z $cleaned ]] && cleaned="$fallback"
  printf '%s' "$cleaned"
}

log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die(){ log "ERROR: $*"; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --current) CURRENT="$2"; shift 2;;
    --new) NEW_FILE="$2"; shift 2;;
    --url) SUB_URL="$2"; shift 2;;
    --output) OUTPUT="$2"; shift 2;;
    --apply) APPLY=1; shift;;
    --auto-append-new) AUTO_APPEND=1; shift;;
    --groups) GROUPS="$2"; shift 2;;
    --backup-dir) BACKUP_DIR="$2"; shift 2;;
    --keep-temp) KEEP_TEMP=1; shift;;
    --screen-timeout)
      # 取值: tag / drop
      SCREEN_TIMEOUT_MODE="$2"; shift 2;;
    --timeout-threshold)
      TIMEOUT_THRESHOLD_MS="$2"; shift 2;;
    --slow-suffix)
      HIGH_TIMEOUT_SUFFIX="$2"; shift 2;;
    --connect-timeout)
      PROBE_CONNECT_TIMEOUT="$2"; shift 2;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \?//' | sed -n '1,120p'; exit 0;;
    *) die "未知参数: $1";;
  esac
done

[[ -f $CURRENT ]] || die "当前配置不存在: $CURRENT"

TMP_DIR=$(mktemp -d /tmp/merge_sub.XXXXXX)
trap '[[ $KEEP_TEMP -eq 1 ]] || rm -rf "$TMP_DIR"' EXIT

if [[ -n $SUB_URL ]]; then
  need curl
  NEW_FILE="$TMP_DIR/sub_new.yaml"
  log "下载订阅: $SUB_URL"
  if ! curl -fsSL --retry 3 --connect-timeout 8 "$SUB_URL" -o "$NEW_FILE"; then
    die "下载失败"
  fi

  # 若不含 proxies: 关键字，尝试识别为 base64 或纯 trojan 列表并转换
  if ! grep -q '^proxies:' "$NEW_FILE"; then
    # 检测内容是否 base64 (只含 base64 字符且长度>0)
    if grep -q '^[A-Za-z0-9+/=][:A-Za-z0-9+/=]*' "$NEW_FILE"; then
      if command -v base64 >/dev/null 2>&1; then
        DEC_FILE="$TMP_DIR/decoded.txt"
        if base64 -d "$NEW_FILE" > "$DEC_FILE" 2>/dev/null; then
          # 若解码后含 trojan:// 则采用解码内容
          if grep -qi 'trojan://' "$DEC_FILE"; then
            mv "$DEC_FILE" "$NEW_FILE"
          else
            rm -f "$DEC_FILE"
          fi
        fi
      fi
    fi
    # 若仍无 proxies: 且包含 trojan:// 行，则转换为 Clash proxies 块
    if ! grep -q '^proxies:' "$NEW_FILE" && grep -qi 'trojan://' "$NEW_FILE"; then
      TO_YAML="$TMP_DIR/converted_proxies.yaml"
      echo 'proxies:' > "$TO_YAML"
      # 构建旧配置 server:port -> 原名称 的区域映射
      declare -A OLD_REGION_MAP
      while IFS= read -r oline; do
        [[ $oline =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue
        oname=$(echo "$oline" | sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p")
        ohost=$(echo "$oline" | sed -n "s/.*server:[[:space:]]*\([^,'} ]*\).*/\1/p")
        oport=$(echo "$oline" | sed -n "s/.*port:[[:space:]]*\([0-9]\+\).*/\1/p")
        [[ -z $ohost || -z $oport || -z $oname ]] && continue
        region=""
        for kw in 新加坡 日本 香港 美国 英国 越南 印尼 泰国 马来西亚 加拿大 韩国 俄罗斯 土耳其 德国 巴西 阿联酋 台湾省 台湾; do
          if [[ $oname == *$kw* ]]; then region=$kw; break; fi
        done
        [[ -n $region ]] && OLD_REGION_MAP["$ohost:$oport"]="$region"
      done < "$CURRENT"

      # 端口前缀 -> 区域 推断函数 (仅在旧映射缺失时使用)
      infer_region(){
        local p="$1"
        case $p in
          41*) echo 日本;;
          42*) echo 新加坡;;
          43*) echo 香港;;
          44*) echo 印尼;;
          45*) echo 韩国;;
          46*) echo 美国;;
          47*) echo 英国;;
          49*) echo 印度;;
          51*) echo 加拿大;;
          52*) echo 德国;;
          53*) echo 越南;;
          54*) echo 俄罗斯;;
          55*) echo 巴西;;
          56*) echo 土耳其;;
          57*) echo 巴西;;
          58*) echo 阿联酋;;
          59*) echo 台湾;;
          60*) echo 台湾;;
          61*) echo 泰国;;
          62*) echo 马来西亚;;
          *)   echo 未知;;
        esac
      }

      declare -A REGION_SEQ
      declare -A SEEN_SIG
      while IFS= read -r line; do
        [[ $line == trojan://* ]] || continue
        url_part=${line#trojan://}
        name_part=""
        if [[ $url_part == *#* ]]; then
          name_part=${url_part#*#}
          url_part=${url_part%%#*}
        fi
        pass_part=${url_part%%@*}
        rest=${url_part#*@}
        [[ $rest == "$url_part" ]] && continue
        hostport=${rest%%\?*}
        query=""; [[ $rest == *\?* ]] && query=${rest#*\?}
        host=${hostport%%:*}; port=${hostport##*:}
        [[ -z $host || -z $port || -z $pass_part ]] && continue
        # 过滤统计/到期类条目
        if echo "$name_part" | grep -Eq '(剩余流量|到期|过期|套餐)'; then
          continue
        fi
        sni=""; allow=""
        IFS='&' read -r -a qarr <<< "$query"
        for kv in "${qarr[@]}"; do
          k=${kv%%=*}; v=${kv#*=}
          [[ $k == sni || $k == peer ]] && sni=$v
          [[ $k == allowInsecure && $v == 1 ]] && allow=1
        done
        sig="${host}:${port}:${pass_part}"
        [[ -n ${SEEN_SIG[$sig]:-} ]] && continue
        SEEN_SIG[$sig]=1
        region=${OLD_REGION_MAP["$host:$port"]:-}
        [[ -z $region || $region == 未知 ]] && region=$(infer_region "$port")
        if [[ $region == 未知 ]]; then
          # 尝试从原始 name_part 解码出区域关键词
            dec_try=$(sanitize_name "$name_part" "")
            for kw in 新加坡 日本 香港 美国 英国 越南 印尼 泰国 马来西亚 加拿大 韩国 俄罗斯 土耳其 德国 巴西 阿联酋 台湾; do
              if [[ $dec_try == *$kw* ]]; then region=$kw; break; fi
            done
        fi
        # 序号自增
        cur=${REGION_SEQ[$region]:-0}; cur=$((cur+1)); REGION_SEQ[$region]=$cur
        seq=$(printf '%02d' "$cur")
        gen_name="${region}${seq}"
        esc_name=${gen_name//"'"/"'\\''"}
        printf "    - { name: '%s', type: trojan, server: %s, port: %s, password: %s, udp: true" "$esc_name" "$host" "$port" "$pass_part" >> "$TO_YAML"
        [[ -n $sni ]] && printf ", sni: %s" "$sni" >> "$TO_YAML"
        printf ", skip-cert-verify: true }\n" >> "$TO_YAML"
      done < "$NEW_FILE"
      mv "$TO_YAML" "$NEW_FILE"
      log "已将原始 trojan 列表转换 (已丢弃统计/到期/emoji)"
      # 自动打开追加
      AUTO_APPEND=1
    fi
  fi
fi

[[ -n $NEW_FILE && -f $NEW_FILE ]] || die "未提供 --new 或 --url 获得的订阅文件"

# 规范化换行 (可选)
if command -v dos2unix >/dev/null 2>&1; then dos2unix -q "$NEW_FILE" "$CURRENT" || true; fi

OLD_PROXIES_BLOCK="$TMP_DIR/old_proxies.yaml"
NEW_PROXIES_BLOCK="$TMP_DIR/new_proxies.yaml"

# 提取 proxies 块函数
extract_proxies(){
  local file="$1" out="$2"
  awk '
    /^proxies:/ {_inblk=1; print; next}
    /^[A-Za-z0-9_-]+:/ { if(_inblk){ exit } }
    _inblk { print }
  ' "$file" > "$out"
  if ! grep -q '^proxies:' "$out"; then
    die "未在 $file 中找到 proxies 块"
  fi
}

extract_proxies "$CURRENT" "$OLD_PROXIES_BLOCK"
extract_proxies "$NEW_FILE" "$NEW_PROXIES_BLOCK"

log "旧 proxies 行数: $(wc -l < "$OLD_PROXIES_BLOCK")"
log "新 proxies 行数: $(wc -l < "$NEW_PROXIES_BLOCK")"

# ---------------------------------------------
# 高延迟节点探测 (仅对新订阅节点, 以 server:port 为键)
# 使用 bash 并发 + timeout + TCP 半连接 (bash 内置 /dev/tcp) 方式, 避免引入额外依赖。
# 判断逻辑: 建立 TCP 连接耗时 > TIMEOUT_THRESHOLD_MS 视为高延迟; 连接失败或超时也视为高延迟。
# tag: 追加后缀; drop: 从 NEW_PROXIES_BLOCK 中移除该节点行。
# ---------------------------------------------
if [[ -n $SCREEN_TIMEOUT_MODE ]]; then
  case $SCREEN_TIMEOUT_MODE in tag|drop) ;; * ) die "--screen-timeout 只接受 tag|drop";; esac
  log "执行高延迟筛选: 模式=$SCREEN_TIMEOUT_MODE 阈值=${TIMEOUT_THRESHOLD_MS}ms connect-timeout=${PROBE_CONNECT_TIMEOUT}s"
  probe_tmp_dir="$TMP_DIR/probe"; mkdir -p "$probe_tmp_dir"
  mapfile -t new_lines < <(grep -n '^[[:space:]]*-[[:space:]]*{' "$NEW_PROXIES_BLOCK")
  declare -A LINE_MAP INDEX_TO_NAME INDEX_TO_SIG
  idx=0
  for entry in "${new_lines[@]}"; do
    lnum=${entry%%:*}; line=${entry#*:}
    name=$(echo "$line" | sed -n "s/.*name:[[:space:]]*['"]\?\([^,'}\"]*\).*/\1/p")
    server=$(echo "$line" | sed -n "s/.*server:[[:space:]]*\([^,'} ]*\).*/\1/p")
    port=$(echo "$line" | sed -n "s/.*port:[[:space:]]*\([0-9]\+\).*/\1/p")
    [[ -z $server || -z $port || -z $name ]] && continue
    sig="$server:$port"
    LINE_MAP[$sig]="$lnum"
    INDEX_TO_NAME[$idx]="$name"
    INDEX_TO_SIG[$idx]="$sig"
    idx=$((idx+1))
  done
  total=$idx
  log "待探测节点数: $total"
  # 并发探测 (限制并发数以避免过多文件描述符使用)
  MAX_JOBS=32
  results_file="$probe_tmp_dir/results.tsv"; : > "$results_file"
  run_probe(){
    local i="$1"; local sig="${INDEX_TO_SIG[$i]}"; local name="${INDEX_TO_NAME[$i]}"; local host=${sig%:*}; local port=${sig##*:}
    local start end ms status
    start=$(date +%s%3N 2>/dev/null || perl -MTime::HiRes=time -e 'printf("%d", time()*1000)')
    if timeout "$PROBE_CONNECT_TIMEOUT" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
      end=$(date +%s%3N 2>/dev/null || perl -MTime::HiRes=time -e 'printf("%d", time()*1000)')
      ms=$((end-start))
      status=OK
    else
      end=$(date +%s%3N 2>/dev/null || perl -MTime::HiRes=time -e 'printf("%d", time()*1000)')
      ms=$((end-start))
      status=FAIL
    fi
    printf '%s\t%s\t%s\t%s\n' "$sig" "$name" "$ms" "$status" >> "$results_file"
  }
  job_count=0
  for ((i=0;i<total;i++)); do
    run_probe "$i" &
    job_count=$((job_count+1))
    if (( job_count % MAX_JOBS == 0 )); then wait; fi
  done
  wait
  slow_list="$probe_tmp_dir/slow.txt"; : > "$slow_list"
  while IFS=$'\t' read -r sig name ms status; do
    if [[ $status != OK || $ms -ge $TIMEOUT_THRESHOLD_MS ]]; then
      echo "$sig|$name|$ms|$status" >> "$slow_list"
    fi
  done < "$results_file"
  slow_cnt=$(wc -l < "$slow_list" || echo 0)
  log "高延迟/失败节点: $slow_cnt"
  if (( slow_cnt > 0 )); then
    if [[ $SCREEN_TIMEOUT_MODE == drop ]]; then
      # 构建需要删除的行号集合
      del_tmp="$probe_tmp_dir/del_lines.txt"; : > "$del_tmp"
      while IFS='|' read -r sig name ms status; do
        echo "${LINE_MAP[$sig]}" >> "$del_tmp"
      done < "$slow_list"
      sort -nr "$del_tmp" -o "$del_tmp"
      # 逐行删除 (从后往前)
      cp "$NEW_PROXIES_BLOCK" "$NEW_PROXIES_BLOCK.tmp"
      awk -v delf="$del_tmp" 'BEGIN{while((getline l<delf)>0){del[l]=1}} {if(!del[FNR])print}' "$NEW_PROXIES_BLOCK.tmp" > "$NEW_PROXIES_BLOCK"
      rm -f "$NEW_PROXIES_BLOCK.tmp"
      log "已删除高延迟节点 (drop 模式)"
    else
      # tag 模式: 修改对应行，追加后缀 (若未已有)
      cp "$NEW_PROXIES_BLOCK" "$NEW_PROXIES_BLOCK.tmp"; : > "$NEW_PROXIES_BLOCK"
      while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*-[[:space:]]*\{ ]]; then
          name=$(echo "$line" | sed -n "s/.*name:[[:space:]]*['"]\?\([^,'}\"]*\).*/\1/p")
          server=$(echo "$line" | sed -n "s/.*server:[[:space:]]*\([^,'} ]*\).*/\1/p")
          port=$(echo "$line" | sed -n "s/.*port:[[:space:]]*\([0-9]\+\).*/\1/p")
          sig="$server:$port"
          if grep -q "^$sig|$name|" "$slow_list" 2>/dev/null; then
            if [[ $name != *$HIGH_TIMEOUT_SUFFIX ]]; then
              esc_new_name=${name//"'"/"'\\'"}
              line=$(echo "$line" | sed "s/name:[[:space:]]*['\"]\?$name['\",]/name: '$name$HIGH_TIMEOUT_SUFFIX',/")
            fi
          fi
        fi
        echo "$line" >> "$NEW_PROXIES_BLOCK"
      done < "$NEW_PROXIES_BLOCK.tmp"
      rm -f "$NEW_PROXIES_BLOCK.tmp"
      log "已为高延迟节点追加后缀 $HIGH_TIMEOUT_SUFFIX (tag 模式)"
    fi
    log "慢节点列表 (sig|name|ms|status):"; sed 's/^/  - /' "$slow_list" >&2
  fi
fi

set +u  # 暂停 nounset 以安全处理可能为空的关联数组
# 计算差异 (added / removed / changed)
declare -A OLD_NODE_MAP NEW_NODE_MAP
declare -A OLD_ONLY NEW_ONLY CHANGED

parse_proxy_block(){
  local file="$1" prefix="$2"; local line name server port password sig
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue
    # 抽取字段 (容错: 仅截取到逗号或右花括号前)
    name=$(echo "$line" | sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p")
    server=$(echo "$line" | sed -n "s/.*server:[[:space:]]*\([^,'} ]*\).*/\1/p")
    port=$(echo "$line" | sed -n "s/.*port:[[:space:]]*\([0-9]\+\).*/\1/p")
    password=$(echo "$line" | sed -n "s/.*password:[[:space:]]*\([^,'} ]*\).*/\1/p")
    [[ -z $name ]] && continue
    sig="$server:$port:$password"
    if [[ $prefix == OLD ]]; then
      OLD_NODE_MAP["$name"]="$sig"
    else
      NEW_NODE_MAP["$name"]="$sig"
    fi
  done < "$file"
}

parse_proxy_block "$OLD_PROXIES_BLOCK" OLD
parse_proxy_block "$NEW_PROXIES_BLOCK" NEW

for n in "${!OLD_NODE_MAP[@]}"; do
  if [[ -z ${NEW_NODE_MAP[$n]:-} ]]; then
    OLD_ONLY["$n"]=1
  else
    if [[ ${OLD_NODE_MAP[$n]} != ${NEW_NODE_MAP[$n]} ]]; then
      CHANGED["$n"]=1
    fi
  fi
done
if ((${#NEW_NODE_MAP[@]})); then
  for n in "${!NEW_NODE_MAP[@]}"; do
    [[ -n ${OLD_NODE_MAP[$n]:-} ]] || NEW_ONLY["$n"]=1
  done
fi

new_only_count=0; old_only_count=0; changed_count=0
declare -p NEW_ONLY >/dev/null 2>&1 && new_only_count=${#NEW_ONLY[@]}
declare -p OLD_ONLY >/dev/null 2>&1 && old_only_count=${#OLD_ONLY[@]}
declare -p CHANGED  >/dev/null 2>&1 && changed_count=${#CHANGED[@]}
log "Diff 概要: 新增: $new_only_count 删除: $old_only_count 变更: $changed_count (按 name)"
if (( new_only_count )); then
  printf '%s\n' "  新增:" >&2; for n in "${!NEW_ONLY[@]}"; do echo "    - $n" >&2; done | sort >&2
fi
if (( old_only_count )); then
  printf '%s\n' "  删除:" >&2; for n in "${!OLD_ONLY[@]}"; do echo "    - $n" >&2; done | sort >&2
fi
if (( changed_count )); then
  printf '%s\n' "  变更 (server:port:password) :" >&2; for n in "${!CHANGED[@]}"; do echo "    - $n: ${OLD_NODE_MAP[$n]} -> ${NEW_NODE_MAP[$n]}" >&2; done | sort >&2
fi
set -u  # 恢复 nounset

MERGED="$TMP_DIR/merged.yaml"
awk -v newfile="$NEW_PROXIES_BLOCK" '
  BEGIN{ while((getline l < newfile)>0){ newLines[++n]=l } }
  /^proxies:/ { in_old=1; for(i=1;i<=n;i++) print newLines[i]; next }
  /^[A-Za-z0-9_-]+:/ { if(in_old){ in_old=0 } }
  in_old { next }
  { print }
' "$CURRENT" > "$MERGED"

[[ -s $MERGED ]] || die "合并结果为空"

############################################
# 改进: 收集新节点名称 & 分组名称 + 缺失检测
############################################

# 在缺失检测之前: 依据 server:port:password 签名将分组中旧名称替换为新名称
# 构建 sig -> 新名称 映射
declare -A SIG_TO_NEW_NAME
for nn in "${!NEW_NODE_MAP[@]}"; do
  sig=${NEW_NODE_MAP[$nn]}
  SIG_TO_NEW_NAME[$sig]="$nn"
done
declare -A OLDNAME_TO_NEW
for on in "${!OLD_NODE_MAP[@]}"; do
  osig=${OLD_NODE_MAP[$on]}
  if [[ -n ${SIG_TO_NEW_NAME[$osig]:-} ]]; then
    OLDNAME_TO_NEW[$on]="${SIG_TO_NEW_NAME[$osig]}"
  fi
done

# 若存在需要替换的名称，重写 MERGED 中的分组行
if ((${#OLDNAME_TO_NEW[@]})); then
  TMP_RNM="$TMP_DIR/renamed_groups.yaml"; > "$TMP_RNM"
  while IFS= read -r line; do
    if [[ $line =~ proxies:.*\[.*\] ]]; then
      inside=${line#*\[}; inside=${inside%]*}
      IFS=',' read -r -a arr <<< "$inside"
      changed=0
      for i in "${!arr[@]}"; do
        name=$(echo "${arr[$i]}" | sed "s/^['\" ]*//; s/['\" ]*$//")
        if [[ -n ${OLDNAME_TO_NEW[$name]:-} ]]; then
          arr[$i]="${OLDNAME_TO_NEW[$name]}"; changed=1
        fi
      done
      if ((changed)); then
        new_inside=$(IFS=','; echo "${arr[*]}")
        new_inside=$(echo "$new_inside" | sed 's/, */, /g')
        prefix=${line%%[*]*}
        line="$prefix[$new_inside] }"
      fi
    fi
    echo "$line" >> "$TMP_RNM"
  done < "$MERGED"
  mv "$TMP_RNM" "$MERGED"
fi

# 规范化/重建目标分组 proxies 列表，去除旧名称与统计/到期/广告类条目以及重复追加残影
if [[ $AUTO_APPEND -eq 1 ]]; then
  # 收集所有新节点名称 (稍后仍会再次解析 NEW_PROXIES_BLOCK, 此处重复无碍)
  declare -A ALL_NEW_NAME_SET
  while IFS= read -r pline; do
    [[ $pline =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue
    n=$(echo "$pline" | sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p")
    [[ -n $n ]] && ALL_NEW_NAME_SET[$n]=1
  done < "$NEW_PROXIES_BLOCK"

  # 把新名称按字典序排序
  NEW_SORTED_NAMES=$(printf '%s\n' "${!ALL_NEW_NAME_SET[@]}" | sort)
  # 过滤函数: 跳过 meta/统计
  is_meta(){ [[ $1 =~ 剩余流量|到期|过期|套餐|官网|防丢失|推广 ]]; }

  TMP_REBUILD="$TMP_DIR/rebuilt_groups.yaml"; > "$TMP_REBUILD"
  while IFS= read -r line; do
  if [[ $line =~ ^[[:space:]]*-[[:space:]]*\{[[:space:]]*name:[[:space:]]*(西瓜加速|自动选择|故障转移)[,}\ ] ]]; then
      gname=$(echo "$line" | sed -n "s/.*name:[[:space:]]*\([^,}]*\).*/\1/p" | sed "s/[ '\"]//g")
      # 构建新的列表
      rebuilt=()
      case $gname in
        西瓜加速)
          rebuilt+=(自动选择 故障转移)
          ;;
        自动选择|故障转移)
          # 不预置其它组
          ;;
      esac
      while IFS= read -r nm; do
        [[ -z $nm ]] && continue
        is_meta "$nm" && continue
        rebuilt+=("$nm")
      done <<< "$NEW_SORTED_NAMES"
      # 去重保持顺序
      declare -A seen_tmp; final=()
      for nm in "${rebuilt[@]}"; do
        [[ -n ${seen_tmp[$nm]:-} ]] && continue
        seen_tmp[$nm]=1; final+=("$nm")
      done
      new_inside=$(IFS=', '; echo "${final[*]}")
      prefix=${line%%proxies:*}
      line="$prefix""proxies: [${new_inside}] }"
    fi
    # 清理可能出现的双重 "]}[" 残影
    line=$(echo "$line" | sed 's/] }\[/] } # DUP_FIX [/')
    echo "$line" >> "$TMP_REBUILD"
  done < "$MERGED"
  mv "$TMP_REBUILD" "$MERGED"
fi

# 若自动选择 / 故障转移 仍为空数组, 用全部新节点填充 (去除 meta)
if [[ $AUTO_APPEND -eq 1 ]]; then
  # 重新获取全新节点列表 (若上面已获取, 变量仍在)
  declare -A FILL_NAME_SET
  while IFS= read -r pline; do
    [[ $pline =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue
    n=$(echo "$pline" | sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p")
    [[ -n $n ]] && FILL_NAME_SET[$n]=1
  done < "$NEW_PROXIES_BLOCK"
  FILL_SORTED=$(printf '%s\n' "${!FILL_NAME_SET[@]}" | sort)
  is_meta(){ [[ $1 =~ 剩余流量|到期|过期|套餐|官网|防丢失|推广 ]]; }
  TMP_FILL="$TMP_DIR/fill_groups.yaml"; > "$TMP_FILL"
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*\{[[:space:]]*name:[[:space:]]*(自动选择|故障转移)[,}\ ].*proxies:[[:space:]]*\[\][[:space:]]*} ]]; then
      gname=$(echo "$line" | sed -n "s/.*name:[[:space:]]*\([^,}]*\).*/\1/p" | sed "s/[ '\"]//g")
      rebuilt=()
      while IFS= read -r nm; do
        [[ -z $nm ]] && continue
        is_meta "$nm" && continue
        rebuilt+=("$nm")
      done <<< "$FILL_SORTED"
      declare -A seen_fill; final=()
      for nm in "${rebuilt[@]}"; do
        [[ -n ${seen_fill[$nm]:-} ]] && continue
        seen_fill[$nm]=1; final+=("$nm")
      done
      new_inside=$(IFS=', '; echo "${final[*]}")
      prefix=${line%%proxies:*}
      line="$prefix""proxies: [${new_inside}] }"
    fi
    echo "$line" >> "$TMP_FILL"
  done < "$MERGED"
  mv "$TMP_FILL" "$MERGED"
fi

# 收集新节点名称 (解析 NEW_PROXIES_BLOCK 中 proxies: 段)
declare -A NEW_NAMES
# 读取 new proxies 块以收集所有 name
{
  capture=0
  while IFS= read -r line; do
    if [[ $line =~ ^proxies: ]]; then capture=1; continue; fi
    [[ $capture -eq 1 ]] || continue
    if [[ $line =~ ^[A-Za-z0-9_-]+: ]]; then # 下一个顶层键结束
      break
    fi
    # 只处理以 "- {" 开头的单行节点定义
    [[ $line =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue
    name=$(echo "$line" | sed -n "s/.*name:[[:space:]]*\([^,}]*\).*/\1/p")
  name=$(echo "$name" | sed "s/^[[:space:]'\"]*//; s/[[:space:]'\"]*$//")
    [[ -n $name ]] && NEW_NAMES["$name"]=1
  done < "$NEW_PROXIES_BLOCK"
}

# 收集分组名称 (用于忽略 group 自身在 proxies 列表中的引用)
declare -A GROUP_NAME_SET
{
  started=0
  while IFS= read -r line; do
    if [[ $line =~ ^proxy-groups: ]]; then started=1; continue; fi
    [[ $started -eq 1 ]] || continue
    [[ $line =~ ^rules: ]] && break
    [[ $line =~ ^[[:space:]]*-[[:space:]]*\{[[:space:]]*name: ]] || continue
    gname=$(echo "$line" | sed -n "s/.*name:[[:space:]]*\([^,}]*\).*/\1/p")
  gname=$(echo "$gname" | sed "s/^[[:space:]'\"]*//; s/[[:space:]'\"]*$//")
    [[ -n $gname ]] && GROUP_NAME_SET["$gname"]=1
  done < "$MERGED"
}

MISSING_REPORT="$TMP_DIR/missing_nodes.txt"; > "$MISSING_REPORT"
while IFS= read -r line; do
  # 仅匹配包含 proxies: [...] 的 group 行
  if [[ $line =~ proxies:.*\[.*\] ]]; then
    inside=${line#*\[}; inside=${inside%]*}
    IFS=',' read -r -a arr <<< "$inside"
    for raw in "${arr[@]}"; do
      name=$(echo "$raw" | sed "s/^['\" ]*//; s/['\" ]*$//")
      [[ -z $name ]] && continue
      # 跳过分组名称
      [[ ${GROUP_NAME_SET[$name]:-} ]] && continue
      # 节点不存在于新 proxies 中则记为缺失
      [[ -z ${NEW_NAMES[$name]:-} ]] && echo "$name" >> "$MISSING_REPORT"
    done
  fi
done < "$MERGED"

if [[ -s $MISSING_REPORT ]]; then
  log "检测到 proxy-groups 引用但新订阅未提供的节点:"
  sort -u "$MISSING_REPORT" | sed 's/^/  - /'
else
  log "proxy-groups 引用节点均在新订阅中存在"
fi

# 检测新订阅中是否有重复名称
NEW_NAME_COUNT=$(
  grep -E '^[[:space:]]*-[[:space:]]*\{' "$NEW_PROXIES_BLOCK" | \
  sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p" | wc -l
)
if (( NEW_NAME_COUNT != ${#NEW_NODE_MAP[@]} )); then
  log "WARNING: 发现可能的重复节点名称 (解析计数 $NEW_NAME_COUNT != 唯一 ${#NEW_NODE_MAP[@]})"
  dup_tmp=$(mktemp)
  grep -E '^[[:space:]]*-[[:space:]]*\{' "$NEW_PROXIES_BLOCK" | \
    sed -n "s/.*name:[[:space:]]*['\"]\?\([^,'}\"]*\).*/\1/p" | sort | uniq -d > "$dup_tmp"
  if [[ -s $dup_tmp ]]; then
    log "重复名称列表:"; sed 's/^/  - /' "$dup_tmp"
  fi
  rm -f "$dup_tmp"
fi

if [[ $AUTO_APPEND -eq 1 ]]; then
  IFS=',' read -r -a GROUP_ARR <<< "$GROUPS"
  TMP_APD="$TMP_DIR/appended.yaml"
  > "$TMP_APD"
  while IFS= read -r line; do
    for g in "${GROUP_ARR[@]}"; do
      if [[ $line =~ name:[[:space:]]*$g[^,]*,.*proxies:.*\[.*\] ]]; then
        prefix=${line%%[[]*}
        inside=${line#*\[}
        inside=${inside%]*}
        declare -A CUR_SET
        IFS=',' read -r -a arr <<< "$inside"
        for raw in "${arr[@]}"; do
          n=$(echo "$raw" | sed "s/^['\" ]*//; s/['\" ]*$//")
          [[ -n $n ]] && CUR_SET["$n"]=1
        done
        ADD_LIST=()
        for n in "${!NEW_NAMES[@]}"; do
          [[ ${CUR_SET[$n]:-} ]] && continue
          ADD_LIST+=("$n")
        done
        if [[ ${#ADD_LIST[@]} -gt 0 ]]; then
          new_inside="$inside, ${ADD_LIST[*]}"
          new_inside=$(echo "$new_inside" | sed 's/, */, /g')
          line="$prefix[$new_inside] }"
        fi
        break
      fi
    done
    echo "$line" >> "$TMP_APD"
  done < "$MERGED"
  mv "$TMP_APD" "$MERGED"
  log "已尝试为分组追加新增节点 (若有)"
fi

if [[ $APPLY -eq 1 ]]; then
  mkdir -p "$BACKUP_DIR"
  backup="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).yaml"
  cp "$CURRENT" "$backup"
  log "已备份原文件到: $backup"
  if [[ -n $OUTPUT ]]; then
    cp "$MERGED" "$OUTPUT"
    cp "$MERGED" "$CURRENT"
    log "已输出合并文件到: $OUTPUT 并覆盖当前配置"
  else
    cp "$MERGED" "$CURRENT"
    log "已覆盖 $CURRENT"
  fi
else
  if [[ -n $OUTPUT ]]; then
    cp "$MERGED" "$OUTPUT"
    log "合并结果写入: $OUTPUT (未覆盖)"
  else
    log "--- 合并结果 (未覆盖) ---"
    cat "$MERGED"
  fi
  log "若要应用请追加 --apply"
fi

exit 0
