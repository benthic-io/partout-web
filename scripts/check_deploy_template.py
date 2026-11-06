#!/usr/bin/env python3
"""Lint deploy/nginx-site.conf.example + deploy/snippets/ (po-security
handoff 55b115bd HIGH-1: the include-ed snippets must be real repo files, and
no add_header block may omit the inheritance-safe matrix).

Rules:
  1. Every `include snippets/NAME;` resolves to deploy/snippets/NAME.
  2. Braces balance; each block's directives are tracked at its own level.
  3. Any block (server or location) whose OWN directive lines contain
     add_header must also include snippets/partout-common-security.conf at
     that same level (nginx does not inherit add_header once you declare it).
  4. Any location whose path starts with /app that adds headers must also
     include snippets/partout-app-security.conf.
  5. Every CSP add_header string must contain object-src 'none' (site,
     legacy-admin, and app variants) — cf0d322b LOW-5, 55b115bd LOW-3.
  6. The app snippet's Report-Only CSP string and a commented
     `# add_header Content-Security-Policy` enforce twin (if present) must be
     identical except the header name.

Usage: python3 scripts/check_deploy_template.py
Exit: 0 clean, 1 violations (printed), 2 missing files.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "deploy" / "nginx-site.conf.example"
SNIPPETS = ROOT / "deploy" / "snippets"
COMMON = "snippets/partout-common-security.conf"
APP = "snippets/partout-app-security.conf"

violations: list[str] = []


def scan(text: str):
    """Quote- and comment-aware block scanner. Yields blocks with the
    directives at their OWN level (a ';'-terminated directive whose quotes
    contain ';' stays one directive — CSP strings depend on this)."""
    lines = [l for l in text.splitlines() if not l.lstrip().startswith("#")]
    s = "\n".join(lines)
    stack: list[dict] = []
    done: list[dict] = []
    buf = ""
    in_q = False
    skipping = False
    for c in s:
        if skipping:
            if c == "\n":
                skipping = False
            continue
        if c == '"':
            in_q = not in_q
            buf += c
        elif not in_q and c == "#":
            skipping = True
        elif not in_q and c == "{":
            stack.append({"path": buf.strip(), "directives": [], "includes": []})
            buf = ""
        elif not in_q and c == "}":
            if buf.strip():
                stack[-1]["directives"].append(buf.strip())
            buf = ""
            block = stack.pop()
            done.append(block)
        elif not in_q and c == ";":
            d = buf.strip()
            buf = ""
            if stack and d:
                stack[-1]["directives"].append(d)
                if d.startswith("include "):
                    stack[-1]["includes"].append(d[len("include "):])
        else:
            buf += c
    if stack:
        violations.append("brace imbalance: unclosed blocks remain")
    if in_q:
        violations.append("unbalanced double quote in template")
    return done


def main() -> int:
    if not TEMPLATE.exists() or not SNIPPETS.is_dir():
        print("error: deploy/ layout missing", file=sys.stderr)
        return 2
    text = TEMPLATE.read_text()
    snippet_texts = {p.name: p.read_text() for p in SNIPPETS.glob("*.conf")}

    # rule 1: includes resolve
    for inc in re.findall(r"include\s+(snippets/[^;]+);", text):
        if not (SNIPPETS / Path(inc).name).exists():
            violations.append(f"include {inc} has no file under deploy/snippets/")

    for block in scan(text):
        body = block["directives"]
        has_ah = any(d.startswith("add_header") for d in body)
        inc_common = any(COMMON in i for i in block["includes"])
        inc_app = any(APP in i for i in block["includes"])
        # rule 3
        if has_ah and not inc_common:
            violations.append(
                f"block '{block['path']}' uses add_header without including {COMMON} "
                "(nginx drops inherited headers the moment you declare one)"
            )
        # rule 4
        if has_ah and "/app" in block["path"]:
            if not inc_app:
                violations.append(
                    f"/app block '{block['path']}' adds headers without {APP}"
                )
        # rule 5
        for d in body:
            if d.startswith("add_header") and "Content-Security-Policy" in d:
                if "object-src 'none'" not in d:
                    violations.append(f"CSP missing object-src 'none': {d[:80]}...")
        # server-block baseline: includes common but must not need app
        # (nothing to assert beyond rule 3/4/5)

    # rule 5b: CSP strings inside the snippet files are just as load-bearing
    for sname, stext in snippet_texts.items():
        for m in re.finditer(
            r"add_header\s+Content-Security-Policy(?:-Report-Only)?\s+\"([^\"]+)\"",
            stext,
        ):
            if "object-src 'none'" not in m.group(1):
                violations.append(
                    f"deploy/snippets/{sname}: CSP missing object-src 'none'"
                )

    # rule 6: app snippet RO string vs any commented enforce twin
    app_snip = snippet_texts.get(Path(APP).name, "")
    ro = re.search(
        r"add_header\s+Content-Security-Policy-Report-Only\s+\"([^\"]+)\"", app_snip
    )
    enf = re.search(
        r"#\s*add_header\s+Content-Security-Policy\s+\"([^\"]+)\"", app_snip
    )
    if ro and enf and ro.group(1) != enf.group(1):
        violations.append("app snippet: enforce twin differs from Report-Only string")
    if not ro:
        violations.append(f"{APP}: no Content-Security-Policy-Report-Only directive found")

    if violations:
        for v in violations:
            print(f"VIOLATION: {v}", file=sys.stderr)
        return 1
    print("deploy template lint clean: snippets resolve, inheritance-safe, "
          "CSPs carry object-src 'none'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
