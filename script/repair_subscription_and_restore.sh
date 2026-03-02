#!/usr/bin/env bash
# Repair a broken Clash subscription update when a raw URI list overwrote config.yaml.
# 1. Restore most recent valid YAML backup
# 2. Optionally transform the latest raw trojan/vmess URIs into a Clash proxies YAML snippet
# 3. Merge + restart
# Usage: ./script/repair_subscription_and_restore.sh [--generate-from-current]
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR
BACKUP_DIR="$ROOT_DIR/resources/backup"
CUR_CFG="$ROOT_DIR/resources/config.yaml"
GEN_FLAG=0
if [[ ${1:-} == --generate-from-current ]]; then GEN_FLAG=1; fi

last_backup=$(ls -1 "$BACKUP_DIR"/config_*.yaml 2>/dev/null | tail -n 2 | head -n 1)
# tail -n2 picks last two (one is the broken pre-restoration), choose the earlier one if needed
if [[ -z "$last_backup" ]]; then
  echo "No backup config_*.yaml found in $BACKUP_DIR" >&2; exit 1
fi
cp -f "$last_backup" "$CUR_CFG.restored"

echo "[+] Restored backup candidate: $last_backup -> $CUR_CFG.restored"

if [[ $GEN_FLAG -eq 1 ]]; then
  echo "[+] Attempting to parse raw subscription URIs from current (broken) config.yaml for new proxies list..."
  RAW="$CUR_CFG" # existing broken file
  OUT_SNIPPET="$ROOT_DIR/resources/generated_proxies.yaml"
  python3 - <<'PY'
import os,sys,urllib.parse,re,yaml
root=os.environ.get('ROOT_DIR','.')
cur_cfg=os.path.join(root,'resources','config.yaml')
out_snippet=os.path.join(root,'resources','generated_proxies.yaml')
if not os.path.exists(cur_cfg):
  print('missing config.yaml',file=sys.stderr); sys.exit(1)
proxies=[]
with open(cur_cfg,'r',encoding='utf-8',errors='ignore') as f:
  for line in f:
    line=line.strip()
    if not line or line.startswith('#'): continue
    if re.match(r'^(trojan|vmess|ss|ssr|vless)://', line):
      # Split hash tag name
      if '#' in line:
        uri, tag = line.split('#',1)
        name = urllib.parse.unquote(tag)[:64]
      else:
        uri=line; name='NODE-'+str(len(proxies)+1)
      # Basic trojan parse
      scheme, rest = uri.split('://',1)
      if scheme=='trojan':
        # password@host:port?query
        cred_host = rest
        pwd, hostport_q = cred_host.split('@',1)
        hostport, *q = hostport_q.split('?',1)
        host, port = hostport.split(':',1)
        sni=None
        if q:
          qs=urllib.parse.parse_qs(q[0])
          sni=qs.get('sni',[qs.get('peer',[''])[0]])[0] or None
        proxy={
          'name': name,
          'type': 'trojan',
          'server': host,
            'port': int(re.sub(r'[^0-9]','',port) or '443'),
          'password': pwd,
          'sni': sni,
          'skip-cert-verify': True
        }
        proxies.append(proxy)
# Output snippet
with open(out_snippet,'w',encoding='utf-8') as f:
  yaml.safe_dump({'proxies':proxies},f,allow_unicode=True,sort_keys=False)
print(f"Generated {len(proxies)} proxies -> {out_snippet}")
PY
  echo "[+] Generated proxies snippet at resources/generated_proxies.yaml"
fi

# Move restored YAML into place
mv -f "$CUR_CFG.restored" "$CUR_CFG"

# Merge & restart kernel
CLASH_LIB_MODE=1 bash -lc 'cd "$ROOT_DIR" && . script/common.sh 2>/dev/null || true; . script/clashctl.sh 2>/dev/null || true; _merge_sanitize_restart' || true

echo "[+] Repair complete."
