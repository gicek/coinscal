#!/usr/bin/env python3
"""Publishes a notarized release (make mac-publish; design in docs/UPDATES.md).

Order: check the notarized zip and DMG, the release notes, and that the build number is higher than the live
appcast's -> sign the zip for Sparkle -> render release notes and appcast.xml -> upload the archives, the notes, and
finally appcast.xml to R2 -> create the GitHub Release. Nothing is uploaded until every check has passed.

Usage: scripts/release/publish.py --version 1.1 --build 2 --min-system 14.0 --dist Build/macOS/Dist \
    --notes Site/releases/1.1.json --work Build/macOS/Publish --sparkle-bin <dir> --key-account com.gicek.coinscal \
    --bucket coinscal-dl --base-url https://dl.coinscal.app --wrangler "npx --yes wrangler@<version>" \
    [--node-bin <dir>] [--dry-run]
"""

from __future__ import annotations

import argparse
import email.utils
import html
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

LANGS = ("en", "zh-Hans", "zh-Hant")
IMMUTABLE = "public, max-age=31536000, immutable"
SHORT = "public, max-age=300"


def fail(message: str) -> None:
    print(f"publish: {message}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def load_notes(path: Path, version: str) -> dict[str, list[str]]:
    """Release notes: {"version": "...", "notes": {"en": [...], "zh-Hans": [...], "zh-Hant": [...]}}."""
    if not path.exists():
        fail(f"release notes missing: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != version:
        fail(f"{path} is for version {data.get('version')!r}, not {version}")
    notes = data.get("notes") or {}
    counts = set()
    for lang in LANGS:
        items = notes.get(lang)
        if not items or not all(isinstance(i, str) and i.strip() for i in items):
            fail(f"{path}: notes for {lang} are missing or empty")
        counts.add(len(items))
    if len(counts) != 1:
        fail(f"{path}: every language must have the same number of items")
    return {lang: notes[lang] for lang in LANGS}


def check_notarized(dist: Path, version: str) -> tuple[Path, Path]:
    zip_path = dist / f"Coinscal-{version}.zip"
    dmg_path = dist / f"Coinscal-{version}.dmg"
    for path in (zip_path, dmg_path):
        if not path.exists():
            fail(f"missing {path}: run make mac-release-notarized first")
    run(["xcrun", "stapler", "validate", "-q", str(dmg_path)])
    with tempfile.TemporaryDirectory() as tmp:
        run(["ditto", "-x", "-k", str(zip_path), tmp])
        app = Path(tmp) / "Coinscal.app"
        run(["xcrun", "stapler", "validate", "-q", str(app)])
        run(["spctl", "--assess", "--type", "execute", str(app)], capture_output=True)
        plist = app / "Contents" / "Info.plist"
        short = run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", str(plist)], capture_output=True).stdout.strip()
        if short != version:
            fail(f"{zip_path} contains version {short}, expected {version}")
    return zip_path, dmg_path


def live_build_number(base_url: str) -> int | None:
    try:
        # Cloudflare's browser integrity check rejects the default Python-urllib User-Agent.
        request = urllib.request.Request(f"{base_url}/appcast.xml", headers={"User-Agent": "Coinscal-publish/1.0"})
        with urllib.request.urlopen(request, timeout=15) as response:
            text = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    match = re.search(r"<sparkle:version>(\d+)</sparkle:version>", text)
    return int(match.group(1)) if match else None


def sign_archive(sparkle_bin: Path, account: str, zip_path: Path) -> tuple[str, str]:
    out = run([str(sparkle_bin / "sign_update"), "--account", account, str(zip_path)], capture_output=True).stdout
    signature = re.search(r'sparkle:edSignature="([^"]+)"', out)
    length = re.search(r'length="(\d+)"', out)
    if not signature or not length:
        fail("sign_update returned no signature")
    return signature.group(1), length.group(1)


def render_notes(version: str, lang: str, items: list[str]) -> str:
    title = html.escape(f"Coinscal {version}")
    rows = "\n".join(f"<li>{html.escape(item)}</li>" for item in items)
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="light dark">
<title>{title}</title>
<style>
body {{ margin: 16px 20px; font: 13px/1.5 -apple-system, "PingFang SC", "PingFang TC", sans-serif; }}
h1 {{ margin: 0 0 10px; font-size: 15px; }}
ul {{ margin: 0; padding-left: 20px; }}
li + li {{ margin-top: 4px; }}
</style>
</head>
<body>
<h1>{title}</h1>
<ul>
{rows}
</ul>
</body>
</html>
"""


def render_appcast(version: str, build: int, min_system: str, base_url: str, zip_name: str, length: str, signature: str) -> str:
    notes = "\n".join(
        f"      <sparkle:releaseNotesLink{'' if lang == 'en' else f' xml:lang={quoteattr(lang)}'}>"
        f"{escape(f'{base_url}/notes/{version}.{lang}.html')}</sparkle:releaseNotesLink>"
        for lang in LANGS
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Coinscal</title>
    <link>{escape(base_url)}/appcast.xml</link>
    <item>
      <title>{escape(version)}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(min_system)}</sparkle:minimumSystemVersion>
{notes}
      <enclosure url={quoteattr(f'{base_url}/{zip_name}')} length={quoteattr(length)} type="application/octet-stream" sparkle:edSignature={quoteattr(signature)}/>
    </item>
  </channel>
</rss>
"""


def main() -> None:
    p = argparse.ArgumentParser(description="Publish a notarized Coinscal release")
    for name in ("version", "min-system", "dist", "notes", "work", "sparkle-bin", "key-account", "bucket", "base-url", "wrangler"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--build", required=True, type=int)
    p.add_argument("--node-bin", default="", help="Node 22+ bin directory to put first on PATH for Wrangler")
    p.add_argument("--dry-run", action="store_true", help="check, sign, and render, but upload nothing")
    a = p.parse_args()

    base_url = a.base_url.rstrip("/")
    notes = load_notes(Path(a.notes), a.version)
    zip_path, dmg_path = check_notarized(Path(a.dist), a.version)
    live = live_build_number(base_url)
    if live is not None and a.build <= live:
        fail(f"build {a.build} is not higher than the live build {live}; raise CURRENT_PROJECT_VERSION")
    if not a.dry_run and shutil.which("gh") is None:
        fail("the GitHub CLI (gh) is required: brew install gh, then gh auth login")
    if not a.dry_run:
        run(["gh", "auth", "status"], capture_output=True)

    print(f"==> Signing {zip_path.name} for Sparkle")
    signature, length = sign_archive(Path(a.sparkle_bin), a.key_account, zip_path)

    work = Path(a.work) / a.version
    shutil.rmtree(work, ignore_errors=True)
    (work / "notes").mkdir(parents=True)
    uploads: list[tuple[str, Path, str, str]] = [
        (zip_path.name, zip_path, "application/zip", IMMUTABLE),
        (dmg_path.name, dmg_path, "application/x-apple-diskimage", IMMUTABLE),
        ("Coinscal.dmg", dmg_path, "application/x-apple-diskimage", SHORT),
    ]
    for lang, items in notes.items():
        page = work / "notes" / f"{a.version}.{lang}.html"
        page.write_text(render_notes(a.version, lang, items), encoding="utf-8")
        uploads.append((f"notes/{page.name}", page, "text/html; charset=utf-8", IMMUTABLE))
    appcast = work / "appcast.xml"
    appcast.write_text(render_appcast(a.version, a.build, a.min_system, base_url, zip_path.name, length, signature), encoding="utf-8")
    # Last, so the feed never points at a file that isn't uploaded yet.
    uploads.append(("appcast.xml", appcast, "application/xml; charset=utf-8", SHORT))
    print(f"==> Rendered {appcast}")

    if a.dry_run:
        print("Dry run: nothing uploaded.")
        return

    wrangler = shlex.split(a.wrangler)
    if a.node_bin:
        os.environ["PATH"] = f"{a.node_bin}{os.pathsep}{os.environ['PATH']}"
    for key, path, content_type, cache in uploads:
        print(f"==> Uploading {key}")
        cmd = wrangler + ["r2", "object", "put", f"{a.bucket}/{key}", "--file", str(path),
                          "--content-type", content_type, "--cache-control", cache, "--remote"]
        # Uploads are idempotent and Wrangler's requests fail transiently now and then: retry before giving up.
        for attempt in range(1, 4):
            if subprocess.run(cmd, text=True).returncode == 0:
                break
            if attempt == 3:
                fail(f"uploading {key} failed 3 times; appcast.xml is uploaded last, so the live feed is unchanged")
            print(f"    retrying {key} ({attempt}/2)")

    notes_md = work / "github-notes.md"
    notes_md.write_text("\n".join(f"- {item}" for item in notes["en"]) + "\n", encoding="utf-8")
    print(f"==> Creating GitHub Release v{a.version}")
    run(["gh", "release", "create", f"v{a.version}", str(zip_path), str(dmg_path),
         "--title", f"Coinscal {a.version}", "--notes-file", str(notes_md)])
    print(f"Published Coinscal {a.version} (build {a.build}) to {base_url} and GitHub.")


if __name__ == "__main__":
    main()
