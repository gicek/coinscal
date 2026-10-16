#!/usr/bin/env python3
"""Local preview of the static website (make site-run).

Serves Site/ the way Workers Static Assets does where it matters for the pages: "/privacy" maps to
privacy.html, unknown paths get 404.html, and the headers in Site/_headers (including the CSP) are applied,
so a CSP mistake shows up locally before a deploy.

Usage: python3 scripts/site/serve.py [--port 8787]
"""

from __future__ import annotations

import argparse
import functools
import http.server
import io
from pathlib import Path

SITE = Path(__file__).resolve().parents[2] / "Site"


def parse_headers(path: Path) -> list[tuple[str, list[tuple[str, str]]]]:
    rules: list[tuple[str, list[tuple[str, str]]]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            rules.append((line.strip(), []))
        elif rules and ":" in line:
            name, value = line.strip().split(":", 1)
            rules[-1][1].append((name.strip(), value.strip()))
    return rules


def matches(pattern: str, url_path: str) -> bool:
    return url_path.startswith(pattern[:-1]) if pattern.endswith("*") else url_path == pattern


class Handler(http.server.SimpleHTTPRequestHandler):
    rules = parse_headers(SITE / "_headers")

    def send_head(self):
        url_path = self.path.split("?", 1)[0]
        target = SITE / url_path.lstrip("/")
        if url_path != "/" and not target.exists() and target.with_suffix(".html").exists():
            self.path = url_path + ".html"
        elif url_path != "/" and not target.exists():
            body = (SITE / "404.html").read_bytes()
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return io.BytesIO(body)
        return super().send_head()

    def end_headers(self):
        url_path = self.path.split("?", 1)[0]
        for pattern, headers in self.rules:
            if matches(pattern, url_path):
                for name, value in headers:
                    self.send_header(name, value)
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    handler = functools.partial(Handler, directory=str(SITE))
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Serving {SITE} at http://localhost:{args.port}/ (Ctrl-C to stop)")
        server.serve_forever()


if __name__ == "__main__":
    main()
