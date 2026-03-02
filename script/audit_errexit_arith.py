#!/usr/bin/env python3
"""audit_errexit_arith.py

Static audit for bash arithmetic commands that can unexpectedly fail under
`set -e` (errexit).

Why this exists
---------------
In bash, an arithmetic command `(( expr ))` returns exit status 1 when `expr`
evaluates to 0. With `set -e` enabled, that can abort scripts unexpectedly.

The classic foot-gun is postfix increment/decrement used as a standalone
command:

  ((var++))   # exits with status 1 when var was 0
  ((var--))   # exits with status 1 when var was 0

This tool flags those patterns only when errexit is enabled at that point in
the file (best-effort state tracking across `set -e` / `set +e`).

Usage
-----
  python3 script/audit_errexit_arith.py
  python3 script/audit_errexit_arith.py --strict
  python3 script/audit_errexit_arith.py --json
  python3 script/audit_errexit_arith.py --files a.sh b.sh

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
from typing import List, Optional, Sequence, Tuple


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

# Standalone postfix arithmetic command. We intentionally only flag the simple
# form to reduce false positives.
RE_POSTFIX_ARITH_CMD = re.compile(
    r"^\s*\(\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*(\+\+|--)\s*\)\)\s*(?:#.*)?$"
)


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

        if strip_comments(line):
            m = RE_HEREDOC.search(line)
            if m:
                blocks.append(Block(start=lineno, end=lineno, text=line.rstrip()))
                heredoc_delim = m.group(2)
                heredoc_strip_tabs = "<<-" in line
                i += 1
                continue

        start = lineno
        text = line.rstrip()
        end = lineno
        while re.search(r"\\\s*$", text):
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
    return RE_SET_PLUS_E.search(line) is not None or RE_SET_PLUS_O_ERREXIT.search(line) is not None


def file_sets_e(lines: List[str]) -> bool:
    for line in lines[:120]:
        if _line_enables_errexit(line):
            return True
    return False


def analyze_file(path: str) -> List[Finding]:
    lines = read_text(path)
    blocks = blocks_from_lines(lines)

    errexit_enabled = file_sets_e(lines)
    findings: List[Finding] = []

    for b in blocks:
        t = b.text
        if not strip_comments(t):
            continue

        if _line_disables_errexit(t):
            errexit_enabled = False
        elif _line_enables_errexit(t):
            errexit_enabled = True

        if not errexit_enabled:
            continue

        m = RE_POSTFIX_ARITH_CMD.match(t)
        if not m:
            continue

        # In `cmd && ...` / `cmd || ...` lists, errexit won't abort, but postfix
        # arithmetic is still confusing. Treat those as non-findings to avoid
        # noise (best-effort).
        if "&&" in t or "||" in t:
            continue

        var = m.group(1)
        op = m.group(2)
        msg = (
            f"Postfix arithmetic command '(({var}{op}))' can return status 1 (when {var} was 0) under set -e; "
            "prefer prefix ++var / assignment, or add an explicit guard."
        )
        findings.append(
            Finding(
                kind="postfix_arith_sete",
                severity="high",
                file=path,
                start=b.start,
                end=b.end,
                message=msg,
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
        payload = [x.__dict__ for x in findings]
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        by_sev = {"high": 0, "medium": 0, "low": 0}
        for x in findings:
            by_sev[x.severity] = by_sev.get(x.severity, 0) + 1

        print("errexit arithmetic static audit")
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
