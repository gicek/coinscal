#!/usr/bin/env python3
"""Publishes a notarized release (make mac-publish; see docs/RELEASING.md).

Validate the notarized archives and notes, sign the ZIP for Sparkle, then check every live appcast.
Upload the archives and notes before the appcasts, and create the GitHub Release last.
A retry with the same archives can resume a partial release after the first appcast is live.

Usage: scripts/release/publish.py --version 1.1 --build 2 --min-system 14.0 --team <team> --dist Build/macOS/Dist \
    --notes docs/release-notes/1.1 --work Build/macOS/Publish --sparkle-bin <dir> --key-account ed25519 \
    --bucket coinscal-dl --base-url https://dl.coinscal.app --wrangler "npx --yes wrangler@<version>" \
    [--node-bin <dir>] [--dry-run]
"""

from __future__ import annotations

import argparse
import email.utils
import hashlib
import html
import json
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from xml.etree import ElementTree
from xml.sax.saxutils import escape, quoteattr

LANGS = ("en", "zh-Hans", "zh-Hant")
IMMUTABLE = "public, max-age=31536000, immutable"
SHORT = "public, max-age=300"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def fail(message: str) -> None:
    print(f"publish: {message}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def load_notes(path: Path, version: str) -> dict[str, list[str]]:
    """Release notes: docs/release-notes/<version>/<lang>.md for every UI language, one "- item" per line,
    with the same number of items in every language."""
    if path.name != version:
        fail(f"{path} is not the notes directory for version {version}")
    notes: dict[str, list[str]] = {}
    for lang in LANGS:
        file = path / f"{lang}.md"
        if not file.exists():
            fail(f"release notes missing: {file}")
        items = []
        for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            if not line.startswith("- ") or not line[2:].strip():
                fail(f"{file}:{number}: every line must be a list item (\"- text\")")
            items.append(line[2:].strip())
        if not items:
            fail(f"{file} has no items")
        notes[lang] = items
    if len({len(items) for items in notes.values()}) != 1:
        fail(f"{path}: every language must have the same number of items")
    return notes


def check_all_notes(root: Path) -> None:
    """Validates every version directory under `root` (make test-mac)."""
    versions = sorted(p for p in root.iterdir() if p.is_dir())
    if not versions:
        fail(f"no release notes under {root}")
    for directory in versions:
        load_notes(directory, directory.name)
        extra = sorted(f.name for f in directory.iterdir() if f.name not in {f"{lang}.md" for lang in LANGS})
        if extra:
            fail(f"{directory}: unexpected files {extra}")
    print(f"release notes: {len(versions)} versions, {len(LANGS)} languages each")


def signing_hash(path: Path, team: str) -> str:
    details = run(["codesign", "--display", "--verbose=4", str(path)], capture_output=True).stderr
    if f"TeamIdentifier={team}" not in details.splitlines() or not re.search(r"^Authority=Developer ID Application:", details, re.M):
        fail(f"{path.name}: expected Developer ID signing by team {team}")
    match = re.search(r"^CDHash=([a-f0-9]+)$", details, re.M)
    if not match:
        fail(f"{path.name}: missing code signing hash")
    return match.group(1)


def check_app(app: Path, version: str, build: int, min_system: str, team: str) -> str:
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    with (app / "Contents" / "Info.plist").open("rb") as plist:
        info = plistlib.load(plist)
    for key, expected in (("CFBundleShortVersionString", version), ("CFBundleVersion", str(build)),
                          ("LSMinimumSystemVersion", min_system)):
        if info.get(key) != expected:
            fail(f"{app}: {key} is {info.get(key)!r}, expected {expected!r}. Rebuild the notarized archives.")
    return signing_hash(app, team)


def check_notarized(dist: Path, version: str, build: int, min_system: str, team: str) -> tuple[Path, Path]:
    zip_path = dist / f"Coinscal-{version}.zip"
    dmg_path = dist / f"Coinscal-{version}.dmg"
    for path in (zip_path, dmg_path):
        if not path.exists():
            fail(f"missing {path}: run make mac-release-notarized first")
    run(["xcrun", "stapler", "validate", "-q", str(dmg_path)])
    run(["codesign", "--verify", "--strict", str(dmg_path)])
    signing_hash(dmg_path, team)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        run(["ditto", "-x", "-k", str(zip_path), str(root / "zip")])
        app = root / "zip" / "Coinscal.app"
        run(["xcrun", "stapler", "validate", "-q", str(app)])
        run(["spctl", "--assess", "--type", "execute", str(app)], capture_output=True)
        archive_hash = check_app(app, version, build, min_system, team)
        mount = root / "dmg"
        mount.mkdir()
        run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg_path)], capture_output=True)
        try:
            if check_app(mount / app.name, version, build, min_system, team) != archive_hash:
                fail("the zip and DMG contain different signed builds")
        finally:
            run(["hdiutil", "detach", str(mount)], capture_output=True)
    return zip_path, dmg_path


def published_item(base_url: str, feed: str) -> tuple[int, str, str, str, str, str] | None:
    try:
        # Cloudflare's browser integrity check rejects the default Python-urllib User-Agent.
        request = urllib.request.Request(f"{base_url}/{feed}?publish-check={time.time_ns()}",
                                         headers={"User-Agent": "Coinscal-publish/1.0", "Cache-Control": "no-cache"})
        with urllib.request.urlopen(request, timeout=15) as response:
            channel = ElementTree.fromstring(response.read()).find("channel")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    item = channel.find("item") if channel is not None else None
    enclosure = item.find("enclosure") if item is not None else None
    if item is None or enclosure is None:
        fail(f"{feed}: no release or enclosure in the live feed")
    build = item.findtext(f"{SPARKLE}version", "")
    if not build.isdecimal():
        fail(f"{feed}: invalid live build number")
    return (int(build), item.findtext(f"{SPARKLE}shortVersionString", ""),
            item.findtext(f"{SPARKLE}minimumSystemVersion", ""), enclosure.get("url", ""),
            enclosure.get("length", ""), enclosure.get(f"{SPARKLE}edSignature", ""))


def completed_appcasts(base_url: str, names: list[str], expected: tuple[int, str, str, str, str, str]) -> set[str]:
    build, version, _, archive_url, _, _ = expected
    completed = set()
    for feed in names:
        live = published_item(base_url, feed)
        if live == expected:
            completed.add(feed)
        elif live is not None and (live[0] >= build or live[1] == version or live[3] == archive_url):
            fail(f"{feed}: build {live[0]} ({live[1]}) already occupies this build or version")
    return completed


def verify_uploaded_dmg(base_url: str, dmg: Path) -> None:
    request = urllib.request.Request(f"{base_url}/{dmg.name}", headers={"User-Agent": "Coinscal-publish/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response, dmg.open("rb") as file:
        def sha256(stream):
            digest = hashlib.sha256()
            for chunk in iter(lambda: stream.read(64 * 1024), b""):
                digest.update(chunk)
            return digest.hexdigest()
        if sha256(response) != sha256(file):
            fail("the local DMG differs from the one already uploaded. Restore the original DMG to resume.")


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


def render_appcast(version: str, build: int, min_system: str, base_url: str, zip_name: str, length: str, signature: str,
                   lang: str | None = None) -> str:
    """The feed with release notes in every language (Sparkle picks by system language), or, with `lang`, the feed
    for one in-app language (`appcast.<lang>.xml`) that carries only that language's notes."""
    if lang:
        notes = f"      <sparkle:releaseNotesLink>{escape(f'{base_url}/notes/{version}.{lang}.html')}</sparkle:releaseNotesLink>"
    else:
        notes = "\n".join(
            f"      <sparkle:releaseNotesLink{'' if code == 'en' else f' xml:lang={quoteattr(code)}'}>"
            f"{escape(f'{base_url}/notes/{version}.{code}.html')}</sparkle:releaseNotesLink>"
            for code in LANGS
        )
    feed = f"appcast.{lang}.xml" if lang else "appcast.xml"
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Coinscal</title>
    <link>{escape(f'{base_url}/{feed}')}</link>
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
    if len(sys.argv) == 3 and sys.argv[1] == "--check-notes":
        check_all_notes(Path(sys.argv[2]))
        return
    p = argparse.ArgumentParser(description="Publish a notarized Coinscal release")
    for name in ("version", "min-system", "team", "dist", "notes", "work", "sparkle-bin", "key-account", "bucket", "base-url", "wrangler"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--build", required=True, type=int)
    p.add_argument("--node-bin", default="", help="Node 22+ bin directory to put first on PATH for Wrangler")
    p.add_argument("--dry-run", action="store_true", help="check, sign, and render, but upload nothing")
    a = p.parse_args()
    if not a.team:
        fail("set DEVELOPMENT_TEAM in local.mk to verify the release signing identity")

    base_url = a.base_url.rstrip("/")
    notes = load_notes(Path(a.notes), a.version)
    zip_path, dmg_path = check_notarized(Path(a.dist), a.version, a.build, a.min_system, a.team)
    if not a.dry_run:
        if shutil.which("gh") is None:
            fail("the GitHub CLI (gh) is required: brew install gh, then gh auth login")
        run(["gh", "auth", "status"], capture_output=True)

    print(f"==> Signing {zip_path.name} for Sparkle")
    signature, length = sign_archive(Path(a.sparkle_bin), a.key_account, zip_path)
    feed_names = [f"appcast.{lang}.xml" for lang in LANGS] + ["appcast.xml"]
    expected = (a.build, a.version, a.min_system, f"{base_url}/{zip_path.name}", length, signature)
    completed_feeds = completed_appcasts(base_url, feed_names, expected)
    if completed_feeds:
        verify_uploaded_dmg(base_url, dmg_path)

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
    feed_args = (a.version, a.build, a.min_system, base_url, zip_path.name, length, signature)
    # One feed per in-app language (what current builds read), then the all-language feed for older builds.
    # Feeds go last, so they never point at a file that isn't uploaded yet.
    for lang in LANGS:
        feed = work / f"appcast.{lang}.xml"
        feed.write_text(render_appcast(*feed_args, lang=lang), encoding="utf-8")
        uploads.append((feed.name, feed, "application/xml; charset=utf-8", SHORT))
    appcast = work / "appcast.xml"
    appcast.write_text(render_appcast(*feed_args), encoding="utf-8")
    uploads.append(("appcast.xml", appcast, "application/xml; charset=utf-8", SHORT))
    print(f"==> Rendered {appcast} and the per-language feeds")

    if a.dry_run:
        print("Dry run: nothing uploaded.")
        return

    wrangler = shlex.split(a.wrangler)
    if a.node_bin:
        os.environ["PATH"] = f"{a.node_bin}{os.pathsep}{os.environ['PATH']}"
    for key, path, content_type, cache in uploads:
        if completed_feeds and (key not in feed_names or key in completed_feeds):
            continue  # Once any intended feed is live, archives and notes were uploaded before it.
        print(f"==> Uploading {key}")
        cmd = wrangler + ["r2", "object", "put", f"{a.bucket}/{key}", "--file", str(path),
                          "--content-type", content_type, "--cache-control", cache, "--remote"]
        # Uploads are idempotent and Wrangler's requests fail transiently now and then: retry before giving up.
        for attempt in range(1, 4):
            if subprocess.run(cmd, text=True).returncode == 0:
                break
            if attempt == 3:
                fail(f"uploading {key} failed 3 times. Earlier uploads may be live. Retry with the original archives and notes.")
            print(f"    retrying {key} ({attempt}/2)")

    notes_md = work / "github-notes.md"
    notes_md.write_text("\n".join(f"- {item}" for item in notes["en"]) + "\n", encoding="utf-8")
    print(f"==> Creating GitHub Release v{a.version}")
    if completed_feeds:
        existing = subprocess.run(["gh", "release", "view", f"v{a.version}", "--json", "assets"],
                                  capture_output=True, text=True)
        if existing.returncode == 0:
            assets = {asset["name"] for asset in json.loads(existing.stdout)["assets"]}
            if {zip_path.name, dmg_path.name} <= assets:
                print(f"Coinscal {a.version} (build {a.build}) is already published.")
                return
            fail(f"GitHub Release v{a.version} exists with missing assets. Upload the original archives to that release.")
    run(["gh", "release", "create", f"v{a.version}", str(zip_path), str(dmg_path),
         "--title", f"Coinscal {a.version}", "--notes-file", str(notes_md)])
    print(f"Published Coinscal {a.version} (build {a.build}) to {base_url} and GitHub.")


if __name__ == "__main__":
    main()
