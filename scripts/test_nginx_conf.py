#!/usr/bin/env python3
"""Run `nginx -t` against deploy/nginx-site.conf.example with its real
snippets — the acceptance test po-security asked for (handoff 55b115bd-1):
"real snippet files installed and nginx -t passes". Builds a throwaway
prefix under /tmp/opencode, injects a self-signed cert and an unprivileged
port so no root or production access is needed.

Usage: python3 scripts/test_nginx_conf.py
Exit: 0 config valid, 2 nginx/openssl missing, 1 test failed.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "deploy" / "nginx-site.conf.example"
SNIPPETS = ROOT / "deploy" / "snippets"


def server_blocks(text: str) -> list[str]:
    """Full top-level server {...} blocks (closing brace at column 0)."""
    blocks, cur, depth, inside = [], None, 0, False
    for line in text.splitlines():
        if not inside and line.startswith("server {"):
            inside, depth, cur = True, 0, []
        if inside:
            cur.append(line)
            depth += line.count("{") - line.count("}")
            if depth == 0:
                blocks.append("\n".join(cur))
                inside, cur = False, None
    return blocks


def main() -> int:
    nginx = shutil.which("nginx")
    openssl = shutil.which("openssl")
    if not nginx or not openssl:
        print("error: nginx and openssl are required for this test", file=sys.stderr)
        return 2
    text = TEMPLATE.read_text()
    blocks = server_blocks(text)
    if len(blocks) != 2:
        print(f"error: expected 2 server blocks in template, found {len(blocks)}",
              file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(dir="/tmp/opencode", prefix="nginx-t.") as t:
        tmp = Path(t)
        (tmp / "snippets").mkdir()
        shutil.copy(SNIPPETS / "partout-common-security.conf", tmp / "snippets")
        shutil.copy(SNIPPETS / "partout-app-security.conf", tmp / "snippets")
        subprocess.run(
            [openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", str(tmp / "test.key"), "-out", str(tmp / "test.crt"),
             "-days", "1", "-subj", "/CN=partout.test"],
            check=True, capture_output=True,
        )
        # first (443) block: unprivileged port + throwaway cert, everything else verbatim
        primary = re.sub(
            r"^  listen 443 ssl;$",
            f"  listen 127.0.0.1:8443 ssl;\n  ssl_certificate {tmp}/test.crt;\n"
            f"  ssl_certificate_key {tmp}/test.key;",
            blocks[0], count=1, flags=re.M,
        )
        # second (80) block: nginx -t binds sockets, 80 needs root
        secondary = re.sub(
            r"^  listen 80;$", "  listen 127.0.0.1:8081;", blocks[1], count=1, flags=re.M,
        )
        (tmp / "nginx.conf").write_text(
            "pid " + str(tmp / "nginx.pid") + ";\n"
            "error_log " + str(tmp / "error.log") + ";\n"
            "events { worker_connections 64; }\n"
            "http {\n"
            "  client_body_temp_path " + str(tmp / "cb") + ";\n"
            "  proxy_temp_path " + str(tmp / "pt") + ";\n"
            "  fastcgi_temp_path " + str(tmp / "ft") + ";\n"
            "  uwsgi_temp_path " + str(tmp / "ut") + ";\n"
            "  scgi_temp_path " + str(tmp / "st") + ";\n"
            "  access_log " + str(tmp / "access.log") + ";\n"
            f"  {primary}\n"
            f"  {secondary}\n"
            "}\n"
        )
        r = subprocess.run(
            [nginx, "-t", "-c", str(tmp / "nginx.conf"), "-p", str(tmp),
             "-e", str(tmp / "error.log")],
            capture_output=True, text=True,
        )
        sys.stderr.write(r.stderr)
        if r.returncode != 0:
            print("FAIL: nginx -t rejected the template", file=sys.stderr)
            return 1
        print("nginx -t passed: template + real snippets, includes resolve")
        return 0


if __name__ == "__main__":
    sys.exit(main())
