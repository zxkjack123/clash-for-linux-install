#!/usr/bin/env python3
"""audit_curl_blocks.py

Static audit for curl usage in shell scripts.

Why this exists
---------------
A naive grep on single lines produces many false positives because curl commands are
frequently split across multiple lines with trailing backslashes. This tool merges
"curl blocks" first, then evaluates whether timeouts and failure guards exist.

Checks (heuristic)
------------------
1) Missing curl timeouts
   - --connect-timeout and --max-time (or -m) or "timeout N curl" wrapper.
   - Allows timeouts provided via common option arrays referenced as ${NAME[@]} if
     NAME is defined in the same file and contains timeout flags.

2) curl | jq pipelines under pipefail
   - If the script enables pipefail and uses a curl|jq pipeline without a guard
     (e.g. "|| true" / "|| echo"), transient curl/jq failures may abort the script.

3) Webhook-style POST requests
   - curl -X POST / --request POST without timeouts is flagged as high-risk.

This is intentionally conservative and best-effort. It will not fully parse shell.

Usage
-----
  python3 script/audit_curl_blocks.py            # scan all tracked *.sh
  python3 script/audit_curl_blocks.py --strict   # exit non-zero if high-risk found
  python3 script/audit_curl_blocks.py --files a.sh b.sh

Exit codes
----------
  0: no high-risk findings (or --strict not set)
  1: high-risk findings present (--strict)
  2: tool error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


@dataclass
class Block:
    start: int
    end: int
    text: str


@dataclass
class Finding:
    kind: str
    severity: str  # low|medium|high
    file: str
    start: int
    end: int
    message: str
    excerpt: str


RE_HEREDOC = re.compile(r"<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1")
RE_SET_E_FLAGS = re.compile(r"^\s*set\s+-([A-Za-z]+)\b")
RE_SET_O_ERREXIT = re.compile(r"^\s*set\s+-o\s+errexit\b")
RE_SET_PLUS_E = re.compile(r"^\s*set\s+\+e\b")
RE_SET_PLUS_O_ERREXIT = re.compile(r"^\s*set\s+\+o\s+errexit\b")
RE_SET_PIPEFAIL = re.compile(r"\bpipefail\b")
# Require curl to appear at a command boundary (start/space or common separators),
# not as part of paths like "grep/curl".
RE_CURL_INVOKE = re.compile(r"(^|[\s;(|&])curl\b(?=\s)")
RE_TIMEOUT_WRAPPER = re.compile(r"\btimeout\s+[0-9]+(?:\.[0-9]+)?\s+curl\b")
RE_HAS_CONNECT_TO = re.compile(r"--connect-timeout\b")
RE_HAS_MAX_TIME = re.compile(r"--max-time\b|(?:^|\s)-m\s*[0-9]")
RE_POST = re.compile(r"(?:^|\s)(?:-X\s*POST|--request\s+POST)\b", re.IGNORECASE)
RE_ARRAY_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}")
RE_ARRAY_DEF_ONELINE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\((.*)\)\s*$")
RE_ASSIGN_CURL_SUBSHELL = re.compile(r"^\s*(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*=\$\(\s*curl\b")
RE_PIPE_JQ = re.compile(r"\|\s*jq\b")

# Strings that often mention "curl" but are not curl invocations.
RE_FALSE_POSITIVE_CONTEXT = re.compile(
    r"(^|\s)(command\s+-v\s+curl\b|have\s+curl\b|clash_require_cmd\s+curl\b|missing\+?=\([^\)]*curl[^\)]*\)|for\s+\w+\s+in\s+curl\b|curlimages/curl|User-Agent:\s*curl/)",
    re.IGNORECASE,
)
RE_ECHO_LIKE = re.compile(r"^\s*(echo|printf)\b")


def _run_git(args: Sequence[str]) -> Tuple[int, str, str]:
    try:
        p = subprocess.run(
            ["git", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        return p.returncode, p.stdout, p.stderr
    except Exception as e:
        return 2, "", str(e)


def list_shell_files(repo_root: str) -> List[str]:
    rc, out, _ = _run_git(["ls-files", "*.sh"])
    if rc == 0:
        files = [os.path.join(repo_root, p) for p in out.splitlines() if p.strip()]
        return [f for f in files if os.path.isfile(f)]

    # Fallback: walk directory (best-effort)
    result: List[str] = []
    for root, _, names in os.walk(repo_root):
        for n in names:
            if n.endswith(".sh"):
                result.append(os.path.join(root, n))
    return sorted(result)


def read_text(path: str) -> List[str]:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def strip_comments(line: str) -> str:
    # Best-effort: treat leading '#' as comment.
    if re.match(r"^\s*#", line):
        return ""
    return line


def blocks_from_lines(lines: List[str]) -> List[Block]:
    """Return logical lines by skipping heredocs and merging backslash continuations."""

    blocks: List[Block] = []

    i = 0
    heredoc_delim: Optional[str] = None
    heredoc_strip_tabs = False

    while i < len(lines):
        lineno = i + 1
        line = lines[i]

        if heredoc_delim is not None:
            cur = line
            if heredoc_strip_tabs:
                cur = cur.lstrip("\t")
            if cur.strip() == heredoc_delim:
                heredoc_delim = None
                heredoc_strip_tabs = False
            i += 1
            continue

        # Detect heredoc start (ignore commented lines)
        if strip_comments(line):
            m = RE_HEREDOC.search(line)
            if m:
                blocks.append(Block(start=lineno, end=lineno, text=line.rstrip()))
                heredoc_delim = m.group(2)
                heredoc_strip_tabs = "<<-" in line
                i += 1
                continue

        # Merge backslash continuations
        start = lineno
        text = line.rstrip()
        end = lineno
        while re.search(r"\\\s*$", text):
            # remove trailing backslash + spaces
            text = re.sub(r"\\\s*$", "", text).rstrip()
            i += 1
            if i >= len(lines):
                break
            nxt = lines[i].lstrip()
            text = f"{text} {nxt}".rstrip()
            end = i + 1
        blocks.append(Block(start=start, end=end, text=text))
        i += 1

    return blocks


def parse_option_arrays(lines: List[str]) -> Dict[str, str]:
    """Parse one-line NAME=(...) array definitions; return map of NAME -> raw content."""
    arrays: Dict[str, str] = {}
    for line in lines:
        if not strip_comments(line):
            continue
        m = RE_ARRAY_DEF_ONELINE.match(line)
        if not m:
            continue
        name = m.group(1)
        body = m.group(2)
        arrays[name] = body
    return arrays


def array_has_timeout(body: str) -> bool:
    return ("--connect-timeout" in body) or ("--max-time" in body) or re.search(r"(?:^|\s)-m\s*[0-9]", body) is not None


def _line_enables_errexit(line: str) -> bool:
    if not strip_comments(line):
        return False
    if RE_SET_O_ERREXIT.search(line):
        return True
    m = RE_SET_E_FLAGS.match(line)
    if m and "e" in m.group(1):
        return True
    return False


def _line_disables_errexit(line: str) -> bool:
    if not strip_comments(line):
        return False
    if RE_SET_PLUS_E.search(line) or RE_SET_PLUS_O_ERREXIT.search(line):
        return True
    return False


def file_sets_e(lines: List[str]) -> bool:
    # Detect errexit being enabled (common near the top)
    for line in lines[:120]:
        if _line_enables_errexit(line):
            return True
    return False


def file_sets_pipefail(lines: List[str]) -> bool:
    for blk in blocks_from_lines(lines[:120]):
        line = blk.text
        if not strip_comments(line):
            continue
        if "set" in line and RE_SET_PIPEFAIL.search(line):
            return True
    return False


def has_timeouts(block_text: str, arrays: Dict[str, str]) -> Tuple[bool, bool, List[str]]:
    """Return (has_total_timeout, has_connect_timeout, reasons)."""
    reasons: List[str] = []

    if RE_TIMEOUT_WRAPPER.search(block_text):
        return True, True, ["timeout-wrapper"]

    has_connect = RE_HAS_CONNECT_TO.search(block_text) is not None
    has_total = RE_HAS_MAX_TIME.search(block_text) is not None
    if has_total and has_connect:
        return True, True, ["explicit"]
    if has_total or has_connect:
        reasons.append("partial-explicit")

    # Check referenced option arrays: ${NAME[@]}
    refs = RE_ARRAY_REF.findall(block_text)
    if refs:
        ok_total_any = False
        ok_connect_any = False
        missing: List[str] = []
        for r in refs:
            body = arrays.get(r)
            if body is None:
                missing.append(r)
                continue
            if "--max-time" in body or re.search(r"(?:^|\s)-m\s*[0-9]", body):
                ok_total_any = True
            if "--connect-timeout" in body:
                ok_connect_any = True
        if ok_total_any:
            return True, (has_connect or ok_connect_any), ["opts-array"]
        if missing:
            reasons.append("unknown-opts:" + ",".join(sorted(set(missing))))

    return has_total, has_connect, reasons


def looks_like_curl_invocation(block_text: str) -> bool:
    """Heuristic: detect actual curl execution, not mentions like dependency checks or echoes."""
    t = block_text.strip()
    if not t:
        return False
    if RE_ECHO_LIKE.match(t) and "curl" in t:
        return False
    if RE_FALSE_POSITIVE_CONTEXT.search(t):
        return False
    # Must contain a curl token at a command boundary and followed by whitespace
    if not RE_CURL_INVOKE.search(t):
        return False
    # Exclude common patterns where curl is merely an argument name.
    if re.search(r"\b(clash_require_cmd|require_cmd|need_cmd)\s+curl\b", t):
        return False
    return True


def analyze_file(path: str) -> List[Finding]:
    lines = read_text(path)
    arrays = parse_option_arrays(lines)
    sets_e_default = file_sets_e(lines)
    sets_pipefail = file_sets_pipefail(lines)

    blocks = blocks_from_lines(lines)
    findings: List[Finding] = []

    # Track errexit state across blocks to avoid false positives when scripts
    # temporarily disable `set -e` around a risky call.
    errexit_enabled = sets_e_default

    for b in blocks:
        t = b.text
        if not strip_comments(t):
            continue
        # Update errexit state
        if _line_disables_errexit(t):
            errexit_enabled = False
        elif _line_enables_errexit(t):
            errexit_enabled = True

        if not looks_like_curl_invocation(t):
            continue

        has_total_to, has_connect_to, reasons = has_timeouts(t, arrays)
        is_post = RE_POST.search(t) is not None
        is_pipe_jq = RE_PIPE_JQ.search(t) is not None

        # Missing *total* timeout is the primary hang risk.
        if not has_total_to:
            sev = "high" if is_post else "medium"
            msg = "curl appears to lack a total timeout (--max-time/-m or timeout wrapper)"
            if reasons:
                msg += f" ({'; '.join(reasons)})"
            findings.append(
                Finding(
                    kind="curl_missing_total_timeout",
                    severity=sev,
                    file=path,
                    start=b.start,
                    end=b.end,
                    message=msg,
                    excerpt=t[:240],
                )
            )

        # POST without timeouts
        if is_post and not has_total_to:
            findings.append(
                Finding(
                    kind="webhook_post_no_timeout",
                    severity="high",
                    file=path,
                    start=b.start,
                    end=b.end,
                    message="POST request without timeouts can hang notification/monitoring flow",
                    excerpt=t[:240],
                )
            )

        # Missing connect-timeout is a smaller, but still useful, signal.
        if has_total_to and not has_connect_to:
            findings.append(
                Finding(
                    kind="curl_missing_connect_timeout",
                    severity="low",
                    file=path,
                    start=b.start,
                    end=b.end,
                    message="curl has total timeout but lacks connect-timeout (may delay on DNS/TCP stalls)",
                    excerpt=t[:240],
                )
            )

        # curl | jq under pipefail should be guarded
        if is_pipe_jq and sets_pipefail:
            # Best-effort: require some guard. If jq/curl fails, pipefail can abort scripts.
            guarded = "||" in t
            if not guarded:
                findings.append(
                    Finding(
                        kind="curl_jq_pipefail_unguarded",
                        severity="high" if errexit_enabled else "medium",
                        file=path,
                        start=b.start,
                        end=b.end,
                        message="curl|jq pipeline under pipefail without guard (add '|| true' / fallback)",
                        excerpt=t[:240],
                    )
                )

        # Assignment from $(curl ...) under set -e should be guarded
        if errexit_enabled and RE_ASSIGN_CURL_SUBSHELL.match(t):
            # If it's in an if-condition or has || fallback, it's typically safe.
            if not t.lstrip().startswith("if ") and "||" not in t:
                findings.append(
                    Finding(
                        kind="curl_assign_unprotected_sete",
                        severity="high",
                        file=path,
                        start=b.start,
                        end=b.end,
                        message="var=$(curl ...) under set -e without guard may exit early",
                        excerpt=t[:240],
                    )
                )

    return findings


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--strict", action="store_true", help="Exit non-zero if high-risk findings exist")
    ap.add_argument("--json", dest="json_out", action="store_true", help="Print JSON findings")
    ap.add_argument("--files", nargs="*", default=None, help="Explicit file paths to scan")

    args = ap.parse_args(argv)

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    if args.files:
        files = [os.path.abspath(p) for p in args.files]
    else:
        files = list_shell_files(repo_root)

    findings: List[Finding] = []
    for f in files:
        if not os.path.isfile(f):
            continue
        try:
            findings.extend(analyze_file(f))
        except Exception as e:
            print(f"ERROR: failed to analyze {f}: {e}", file=sys.stderr)
            return 2

    if args.json_out:
        payload = [finding.__dict__ for finding in findings]
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        # Human output
        by_sev = {"high": 0, "medium": 0, "low": 0}
        for x in findings:
            by_sev[x.severity] = by_sev.get(x.severity, 0) + 1

        print("curl static audit (merged blocks)")
        print(f"files scanned: {len(files)}")
        print(f"findings: high={by_sev.get('high',0)} medium={by_sev.get('medium',0)} low={by_sev.get('low',0)}")
        print("")

        for x in findings:
            rel = os.path.relpath(x.file, repo_root)
            loc = f"{rel}:{x.start}" if x.start == x.end else f"{rel}:{x.start}-{x.end}"
            print(f"[{x.severity}] {x.kind} {loc}: {x.message}")
            print(f"  {x.excerpt}")

    if args.strict:
        has_high = any(x.severity == "high" for x in findings)
        return 1 if has_high else 0

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
