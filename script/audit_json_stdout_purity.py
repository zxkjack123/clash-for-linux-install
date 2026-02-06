#!/usr/bin/env python3
"""audit_json_stdout_purity.py

Static audit for scripts that claim to support "JSON mode" output.

Goal
----
When a script is run in JSON mode, stdout should contain *only JSON*.
Human-readable logs must go to stderr.

This tool is intentionally heuristic (shell is hard) but tries to keep false
positives low by:

* Only analyzing scripts that appear to support JSON mode (e.g. '--json',
  'MODE=json', or '... json  # machine-readable JSON output').
* Tracking a minimal notion of "text" vs "json" branches for common patterns:
  - if [[ $MODE == text ]]; then ... else ... fi
  - if [[ $MODE == json ]]; then ... fi
  - case "$MODE" in text) ... ;; json) ... ;; esac
* Treating stdout redirection patterns as safe-by-design, e.g.:
  - if JSON: exec 3>&1; exec 1>&2; JSON_OUT_FD=3

Findings
--------
High:
  echo/printf to stdout (not redirected) in a JSON branch, that does NOT look
  like JSON emission.

Medium:
  echo/printf to stdout in "unknown" context in a JSON-capable script that
  does not use stdout->stderr redirection (might be reachable in JSON mode).

Usage
-----
  python3 script/audit_json_stdout_purity.py
  python3 script/audit_json_stdout_purity.py --strict
  python3 script/audit_json_stdout_purity.py --json
  python3 script/audit_json_stdout_purity.py --files a.sh b.sh
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
    severity: str
    file: str
    start: int
    end: int
    message: str
    excerpt: str


RE_HEREDOC = re.compile(r"<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1")
RE_ECHO_PRINTF = re.compile(r"^\s*(echo|printf)\b")

# JSON mode claim detection.
# IMPORTANT: avoid matching scripts that merely *call* other tools with --json
# (e.g. `tailscale status --json`) or mention JSON in comments.
RE_HAS_CASE_FLAG_JSON = re.compile(r"^\s*--json\)\b", re.MULTILINE)
RE_MODE_ASSIGN = re.compile(r"^\s*MODE\s*=\s*\$\{1:-text\}\b", re.MULTILINE)
RE_MODE_TEST_TEXT = re.compile(r"\b\$?MODE\b\s*==\s*text\b")
RE_MODE_TEST_JSON = re.compile(r"\b\$?MODE\b\s*==\s*json\b")
RE_CASE_JSON_LABEL = re.compile(r"^\s*(json)\)\s*$")
RE_CASE_TEXT_LABEL = re.compile(r"^\s*(text)\)\s*$")

# if conditions on MODE/JSON
RE_IF_MODE_TEXT = re.compile(r"^\s*if\b.*\b\$?MODE\b.*\b(text)\b.*\bthen\b")
RE_IF_MODE_JSON = re.compile(r"^\s*if\b.*\b\$?MODE\b.*\b(json)\b.*\bthen\b")
RE_IF_JSON_FLAG = re.compile(r"^\s*if\b.*\b\$?JSON\b.*\bthen\b")

RE_CASE_MODE = re.compile(r"^\s*case\b.*\b\$?MODE\b.*\bin\b")
RE_ESAC = re.compile(r"^\s*esac\b")
RE_IF = re.compile(r"^\s*if\b")
RE_THEN = re.compile(r"^\s*then\b")
RE_ELSE = re.compile(r"^\s*else\b")
RE_FI = re.compile(r"^\s*fi\b")
RE_CASE = re.compile(r"^\s*case\b")
RE_CASE_BRANCH_END = re.compile(r";;\s*(?:#.*)?$")


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
                heredoc_delim = m.group(2)
                heredoc_strip_tabs = "<<-" in line
                i += 1
                continue

        start = lineno
        text = line.rstrip()
        end = lineno
        while re.search(r"\\\s*$", text):
            text = re.sub(r"\\\\\s*$", "", text).rstrip()
            i += 1
            if i >= len(lines):
                break
            nxt = lines[i].lstrip()
            text = f"{text} {nxt}".rstrip()
            end = i + 1
        blocks.append(Block(start=start, end=end, text=text))
        i += 1
    return blocks


def looks_like_json_emission(cmd: str) -> bool:
    """Heuristic: treat these as intended JSON output, not human logs."""
    s = cmd.strip()
    # echo '{' / echo '}' / echo '[' ...
    if re.search(r"\b(echo|printf)\b\s+['\"]\s*[\[{\]}]", s):
        return True
    # printf '  "key": ...'
    if re.search(r"\bprintf\b\s+['\"][^'\"]*\"[A-Za-z0-9_\-]+\"\s*:\s*", s):
        return True
    # jq is a strong JSON signal
    if re.search(r"\bjq\b\s+(-n|--null-input)\b", s):
        return True
    return False


def stdout_is_redirected_to_stderr_when_json(file_text: str) -> bool:
    """Detect the common safe-by-design pattern: in JSON mode, exec 1>&2."""
    # This is intentionally simple: the pattern is distinctive enough.
    if "exec 1>&2" not in file_text:
        return False
    # Require a nearby JSON marker to reduce accidental matches.
    if re.search(r"\bJSON\b|--json|MODE", file_text) is None:
        return False
    return True


def supports_json_mode(file_text: str) -> bool:
    """Return True if the script itself appears to implement a JSON output mode."""
    if RE_HAS_CASE_FLAG_JSON.search(file_text) is not None:
        return True
    # Positional mode style: MODE=${1:-text} with branches testing MODE for text/json.
    if RE_MODE_ASSIGN.search(file_text) is not None and (
        RE_MODE_TEST_TEXT.search(file_text) is not None or RE_MODE_TEST_JSON.search(file_text) is not None
    ):
        # Require some JSON output signal, otherwise MODE may be unrelated.
        if re.search(r"\bJSON\s+output\b|\bmachine-readable\b|\becho\s+['\"]\{['\"]|\bjq\b\s+-n\b", file_text, re.IGNORECASE):
            return True
    # case "$MODE" in json) ... esac
    if re.search(r"^\s*case\b.*\b\$?MODE\b.*\bin\b", file_text, re.MULTILINE) and re.search(r"^\s*json\)\b", file_text, re.MULTILINE):
        return True
    return False


class IfFrame:
    def __init__(self, then_ctx: str, else_ctx: str, active_ctx: str):
        self.then_ctx = then_ctx
        self.else_ctx = else_ctx
        self.active_ctx = active_ctx  # current for this frame: then_ctx or else_ctx
        self.waiting_for_then = False


class CaseFrame:
    def __init__(self, is_mode_case: bool):
        self.is_mode_case = is_mode_case
        self.active_ctx: str = "unknown"  # current branch context


def analyze_file(path: str) -> List[Finding]:
    lines = read_text(path)
    file_text = "\n".join(lines)

    # Only consider scripts that appear to implement JSON mode themselves.
    if not supports_json_mode(file_text):
        return []

    blocks = blocks_from_lines(lines)
    findings: List[Finding] = []

    has_exec_redirect = stdout_is_redirected_to_stderr_when_json(file_text)

    if_stack: List[IfFrame] = []
    case_stack: List[CaseFrame] = []

    def current_ctx() -> str:
        # Case branches override only when the top case is active
        if case_stack:
            c = case_stack[-1].active_ctx
            if c != "unknown":
                return c
        if if_stack:
            return if_stack[-1].active_ctx
        return "unknown"

    for b in blocks:
        raw = b.text
        t = strip_comments(raw)
        if not t:
            continue
        s = t.strip()

        # Track case on MODE
        if RE_CASE.match(s):
            case_stack.append(CaseFrame(is_mode_case=RE_CASE_MODE.search(s) is not None))

        if case_stack and case_stack[-1].is_mode_case:
            if RE_CASE_TEXT_LABEL.match(s):
                case_stack[-1].active_ctx = "text"
            elif RE_CASE_JSON_LABEL.match(s):
                case_stack[-1].active_ctx = "json"
            elif RE_CASE_BRANCH_END.search(s):
                case_stack[-1].active_ctx = "unknown"

        if RE_ESAC.match(s):
            if case_stack:
                case_stack.pop()

        # Track if/then/else/fi for common MODE/JSON patterns
        if RE_IF.match(s):
            then_ctx = "unknown"
            else_ctx = "unknown"
            if RE_IF_MODE_TEXT.search(s):
                then_ctx = "text"
                else_ctx = "json_possible"
            elif RE_IF_MODE_JSON.search(s):
                then_ctx = "json"
                else_ctx = "text_possible"
            elif RE_IF_JSON_FLAG.search(s):
                # Treat JSON flag condition as json context. This often wraps JSON output.
                then_ctx = "json"
                else_ctx = "unknown"

            frame = IfFrame(then_ctx=then_ctx, else_ctx=else_ctx, active_ctx=then_ctx)
            if "then" not in s:
                frame.waiting_for_then = True
                frame.active_ctx = "unknown"
            if_stack.append(frame)

        if if_stack and if_stack[-1].waiting_for_then and RE_THEN.match(s):
            if_stack[-1].waiting_for_then = False
            if_stack[-1].active_ctx = if_stack[-1].then_ctx

        if RE_ELSE.match(s):
            if if_stack:
                if_stack[-1].active_ctx = if_stack[-1].else_ctx

        if RE_FI.match(s):
            if if_stack:
                if_stack.pop()

        # Single-line guards: [[ $MODE == text ]] && echo ...
        if re.search(r"\b\$?MODE\b.*\btext\b\s*\]\]\s*&&\s*(echo|printf)\b", s):
            continue
        if re.search(r"\b\$?MODE\b.*\bjson\b\s*\]\]\s*&&\s*(echo|printf)\b", s):
            # This is JSON-only output; treat as json context.
            if not looks_like_json_emission(s) and ("&>2" not in s) and (">&2" not in s) and ("1>&2" not in s):
                findings.append(
                    Finding(
                        kind="json_stdout_pollution",
                        severity="high",
                        file=path,
                        start=b.start,
                        end=b.end,
                        message="echo/printf in a JSON-only guard does not look like JSON emission; likely stdout pollution",
                        excerpt=raw[:240],
                    )
                )
            continue

        # If script redirects stdout to stderr in JSON mode, treat most echoes as safe.
        # Still flag pre-redirect emissions as low-risk signals (best-effort: approximate
        # by ignoring this in static mode unless in explicit json branch).
        ctx = current_ctx()

        if RE_ECHO_PRINTF.match(s):
            # stdout -> stderr redirection
            to_stderr = (">&2" in s) or re.search(r"\b1>&2\b", s) is not None
            to_fd = re.search(r">&\s*\"?\$[A-Za-z_][A-Za-z0-9_]*\"?", s) is not None

            # Writing into a pipeline or redirecting stdout to a file is usually not
            # user-visible stdout. (Best-effort: don't over-lint data plumbing.)
            if "|" in s:
                continue
            # stdout redirection: '>' / '>>' / '1>' / '1>>' / '>|'
            if re.search(r"(^|\s)(?:1)?>(?:\||>)?\s*[^&]", s) is not None:
                continue

            if to_stderr:
                continue

            # Writing to a dedicated FD variable (e.g. >&"$JSON_OUT_FD") is allowed.
            if to_fd:
                continue

            # If it looks like JSON output, allow it (it's the *only* thing allowed on stdout in JSON mode).
            if looks_like_json_emission(s):
                continue

            if ctx == "json":
                findings.append(
                    Finding(
                        kind="json_stdout_pollution",
                        severity="high",
                        file=path,
                        start=b.start,
                        end=b.end,
                        message="echo/printf to stdout in JSON branch does not look like JSON; send logs to stderr",
                        excerpt=raw[:240],
                    )
                )
            elif ctx in ("json_possible", "unknown") and not has_exec_redirect:
                findings.append(
                    Finding(
                        kind="json_stdout_pollution_possible",
                        severity="medium" if ctx == "json_possible" else "low",
                        file=path,
                        start=b.start,
                        end=b.end,
                        message="echo/printf to stdout in a JSON-capable script; ensure this cannot run in JSON mode (or redirect to stderr)",
                        excerpt=raw[:240],
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
    scanned = 0
    for f in files:
        if not os.path.isfile(f):
            continue
        scanned += 1
        try:
            findings.extend(analyze_file(f))
        except Exception as e:
            print(f"ERROR: failed to analyze {f}: {e}", file=sys.stderr)
            return 2

    try:
        if args.json_out:
            print(json.dumps([x.__dict__ for x in findings], ensure_ascii=False, indent=2))
        else:
            by_sev = {"high": 0, "medium": 0, "low": 0}
            for x in findings:
                by_sev[x.severity] = by_sev.get(x.severity, 0) + 1

            print("json stdout purity static audit")
            print(f"files scanned: {scanned}")
            print(f"findings: high={by_sev.get('high',0)} medium={by_sev.get('medium',0)} low={by_sev.get('low',0)}")
            print("")
            for x in findings:
                rel = os.path.relpath(x.file, repo_root)
                loc = f"{rel}:{x.start}" if x.start == x.end else f"{rel}:{x.start}-{x.end}"
                print(f"[{x.severity}] {x.kind} {loc}: {x.message}")
                print(f"  {x.excerpt}")
    except BrokenPipeError:
        # Common when output is piped into `head`. Exit cleanly.
        return 0

    if args.strict:
        has_high = any(x.severity == "high" for x in findings)
        return 1 if has_high else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
