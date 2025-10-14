#!/usr/bin/env bash
# Shared network helper functions for quick tests
# Provides: nh_curl_t, nh_grade_time, nh_percent, nh_init_symbols
# Emoji/ASCII fallback controlled by NH_ASCII=1 or TERM=dumb.

# Defaults
: "${NH_DEFAULT_TIMEOUT:=6}"

nh_is_ascii(){ [[ -n "${NH_ASCII:-}" || ${TERM:-xterm} == "dumb" ]]; }

nh_init_symbols(){
  if nh_is_ascii; then
    NH_OK="OK"; NH_FAIL="FAIL"; NH_WARN="WARN"; NH_READY="READY"; NH_PARTIAL="PARTIAL"; NH_ISSUE="ISSUE"
  else
    NH_OK="✅"; NH_FAIL="❌"; NH_WARN="⚠️"; NH_READY="✅ READY"; NH_PARTIAL="⚠️ PARTIAL"; NH_ISSUE="❌ ISSUE"
  fi
}

# Curl probe: prints "code,time_total"; args: url [proxy] [timeout]
nh_curl_t(){
  local url="$1"; local proxy="${2:-}"; local to="${3:-$NH_DEFAULT_TIMEOUT}"; local mt=$((to+4))
  if [[ -n "$proxy" ]]; then
    curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$to" --max-time "$mt" --proxy "$proxy" "$url" 2>/dev/null || echo "000,$to"
  else
    curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$to" --max-time "$mt" "$url" 2>/dev/null || echo "000,$to"
  fi
}

# Time compare and grading without bc; returns A/B/C/D/F given code,time
nh_grade_time(){
  local code="$1"; local t="$2"
  # Non 2xx/3xx -> F
  [[ "$code" =~ ^[23][0-9][0-9]$ ]] || { echo F; return; }
  # Use awk for numeric comparison
  awk -v tt="$t" 'BEGIN{t=tt+0; if(t<=1.5)print "A"; else if(t<=3)print "B"; else if(t<=5)print "C"; else print "D"}'
}

# Integer percent (floor)
nh_percent(){
  awk -v a="$1" -v b="$2" 'BEGIN{ if(b==0)print 0; else print int((a*100)/b) }'
}

# Regex OK per default or provided allow pattern; echoes OK/FAIL
nh_ok_by_code(){
  local code="$1"; local pattern="${2:-^[23][0-9][0-9]$}"
  if [[ "$code" =~ $pattern ]]; then echo OK; else echo FAIL; fi
}
