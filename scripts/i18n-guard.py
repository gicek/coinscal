#!/usr/bin/env python3
"""Three localization guards (project-guide localization.md section 4). Called by `make test-<component>`;
exits with code 1 if any guard fails.

  1. Source scan: fails when source code contains non-source-language text outside localization APIs (literals
     in CJK, Cyrillic, Arabic, and other scripts). A character-level lexer skips comments; both string literals
     and JSX text are checked.
  2. Complete translations: every key has a non-empty translation in every target language, and translations
     have no orphan keys missing from the source language.
  3. Keys match: every literal key in a localization call in source code has an entry in the resources.

Usage:
  python3 scripts/i18n-guard.py --platform apple   --root Apple/Mac [--extra Apple/Shared] --langs en,zh-Hans
  python3 scripts/i18n-guard.py --platform android --root Android --langs en,zh-Hans
  python3 scripts/i18n-guard.py --platform web     --root Web --langs en,zh-Hans [--messages Web/messages]

The first --langs entry is the source language (default en). --min-files asserts that at least N source files
were scanned (default 1; projects should raise it to match their size so a broken path cannot pass silently).
When resources are missing, guards 2/3 report "skipped" but guard 1 still runs.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path

SKIP_DIRS = {"Build", "build", ".build", "DerivedData", "node_modules", ".next", ".open-next", ".gradle", ".kotlin",
             "Tests", "test", "tests", "__tests__", "e2e", "androidTest", "docs", "scripts", ".git"}
SOURCE_EXT = {"apple": {".swift"}, "android": {".kt"}, "web": {".ts", ".tsx", ".js", ".jsx"}}

# Non-source-language scripts (the source language is English by convention): letters from these Unicode blocks
# in a literal are treated as hardcoded UI text
FOREIGN_RANGES = [
    (0x0400, 0x04FF), (0x0590, 0x05FF), (0x0600, 0x06FF), (0x0900, 0x097F), (0x0E00, 0x0E7F),
    (0x3040, 0x30FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xAC00, 0xD7AF), (0xF900, 0xFAFF),
]


def is_foreign_letter(ch: str) -> bool:
    cp = ord(ch)
    return unicodedata.category(ch).startswith("L") and any(a <= cp <= b for a, b in FOREIGN_RANGES)


def iter_source_files(roots: list[Path], exts: set[str]):
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if p.suffix in exts and not (set(p.relative_to(root).parts) & SKIP_DIRS):
                yield p


def tokenize(text: str, lang: str):
    """Yields ("str", content, line) and ("code", content, line); comments are dropped. Supports // /* */ "..." '...' `...`
    and Swift/Kotlin triple quotes."""
    i, n, line = 0, len(text), 1
    buf, buf_line = [], 1

    def flush_code():
        nonlocal buf
        if buf:
            yield ("code", "".join(buf), buf_line)
            buf = []

    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "//":
            yield from flush_code()
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if two == "/*":
            yield from flush_code()
            j = text.find("*/", i + 2)
            seg = text[i:] if j < 0 else text[i:j + 2]
            line += seg.count("\n")
            i = n if j < 0 else j + 2
            buf_line = line
            continue
        if text.startswith('"""', i):
            yield from flush_code()
            j = text.find('"""', i + 3)
            seg = text[i + 3:] if j < 0 else text[i + 3:j]
            yield ("str", seg, line)
            line += seg.count("\n")
            i = n if j < 0 else j + 3
            buf_line = line
            continue
        if c in "\"'`" and (lang != "apple" or c == '"'):
            yield from flush_code()
            q, j, out = c, i + 1, []
            while j < n and text[j] != q:
                if text[j] == "\\" and j + 1 < n:
                    out.append(text[j:j + 2]); j += 2; continue
                if text[j] == "\n" and q != "`":
                    break
                out.append(text[j]); j += 1
            s = "".join(out)
            yield ("str", s, line)
            line += s.count("\n")
            i = j + 1
            buf_line = line
            continue
        if c == "\n":
            line += 1
        buf.append(c)
        i += 1
    yield from flush_code()


APPLE_KEY_CALLS = re.compile(r'(?:String\(localized:|LocalizedStringKey\(|\bText\(|\bLabel\(|\bButton\(|\bToggle\(|\bSection\(|NSLocalizedString\()\s*"((?:[^"\\]|\\.)*)"')
ANDROID_KEY_CALLS = re.compile(r"\bR\.(?:string|plurals)\.([A-Za-z0-9_]+)")
WEB_KEY_CALLS = re.compile(r"\bt\(\s*['\"]([A-Za-z0-9_.\-]+)['\"]")


def lang_to_android_dir(lang: str, source: str) -> str:
    if lang == source:
        return "values"
    parts = lang.split("-")
    return "values-" + parts[0] if len(parts) == 1 else "values-b+" + "+".join(parts)


class Report:
    def __init__(self):
        self.errors: list[str] = []
        self.notes: list[str] = []

    def err(self, m):
        self.errors.append(m)

    def note(self, m):
        self.notes.append(m)


def guard1_source_scan(files: list[Path], platform: str, r: Report) -> None:
    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        for kind, content, line in tokenize(text, platform):
            if kind == "str" or (kind == "code" and platform == "web"):
                bad = [ch for ch in content if is_foreign_letter(ch)]
                if bad:
                    where = "string literal" if kind == "str" else "JSX text"
                    r.err(f"guard 1 {f}:{line} {where} contains non-source-language text \"{''.join(bad[:8])}...\": use the localization API and resource files")


# ---------------- Apple ----------------
def load_xcstrings(paths: list[Path]) -> dict[str, dict]:
    keys: dict[str, dict] = {}
    for p in paths:
        data = json.loads(p.read_text(encoding="utf-8"))
        for k, v in data.get("strings", {}).items():
            keys[k] = v
    return keys


def apple_guards(roots: list[Path], langs: list[str], r: Report) -> list[Path]:
    files = list(iter_source_files(roots, SOURCE_EXT["apple"]))
    guard1_source_scan(files, "apple", r)
    catalogs = [p for root in roots if root.exists() for p in root.rglob("Localizable.xcstrings")
                if not (set(p.parts) & {"Build", "DerivedData"})]
    if not catalogs:
        r.note("guards 2/3 skipped: Localizable.xcstrings not found")
        return files
    strings = load_xcstrings(catalogs)
    source, targets = langs[0], langs[1:]
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        for lang in targets:
            unit = locs.get(lang, {})
            value = unit.get("stringUnit", {}).get("value", "")
            if not value and not unit.get("variations"):
                r.err(f"guard 2 key \"{key}\" is missing the {lang} translation ({catalogs[0]})")
        for lang in locs:
            if lang not in langs:
                r.err(f"guard 2 key \"{key}\" has a translation for undeclared language {lang}: docs/LOCALIZATION.md defines the language set")
    for f in files:
        for m in APPLE_KEY_CALLS.finditer(f.read_text(encoding="utf-8", errors="replace")):
            key = m.group(1)
            if key and "\\(" not in key and key not in strings:
                r.err(f"guard 3 {f} localization key \"{key}\" is not in the String Catalog: build once so Xcode extracts it, or add it manually")
    return files


# ---------------- Android ----------------
def android_strings(path: Path) -> dict[str, bool]:
    """name → translatable"""
    out = {}
    if not path.exists():
        return out
    for el in ET.parse(path).getroot():
        if el.tag in ("string", "plurals", "string-array") and el.get("name"):
            out[el.get("name")] = el.get("translatable", "true") != "false"
    return out


def android_guards(roots: list[Path], langs: list[str], r: Report) -> list[Path]:
    files = list(iter_source_files(roots, SOURCE_EXT["android"]))
    guard1_source_scan(files, "android", r)
    res_dirs = [p for root in roots if root.exists() for p in root.rglob("src/main/res")]
    if not res_dirs:
        r.note("guards 2/3 skipped: src/main/res not found")
        return files
    source = langs[0]
    for res in res_dirs:
        src = android_strings(res / "values" / "strings.xml")
        translatable = {k for k, t in src.items() if t}
        for lang in langs[1:]:
            d = res / lang_to_android_dir(lang, source) / "strings.xml"
            if not d.exists():
                r.err(f"guard 2 missing {d}")
                continue
            tr = set(android_strings(d))
            for k in sorted(translatable - tr):
                r.err(f"guard 2 key \"{k}\" is missing the {lang} translation ({d})")
            for k in sorted(tr - set(src)):
                r.err(f"guard 2 {d} has orphan key \"{k}\" (not in the source language)")
        for f in files:
            for m in ANDROID_KEY_CALLS.finditer(f.read_text(encoding="utf-8", errors="replace")):
                if m.group(1) not in src:
                    r.err(f"guard 3 {f} references R.string.{m.group(1)}, but values/strings.xml has no such key")
    return files


# ---------------- Web ----------------
def flatten(d: dict, prefix: str = "") -> set[str]:
    out = set()
    for k, v in d.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out |= flatten(v, key + ".")
        else:
            out.add(key)
    return out


def web_guards(roots: list[Path], langs: list[str], messages: Path | None, r: Report) -> list[Path]:
    files = list(iter_source_files(roots, SOURCE_EXT["web"]))
    guard1_source_scan(files, "web", r)
    if messages is None:
        for cand in ("messages", "i18n/messages", "src/messages", "locales"):
            if (roots[0] / cand).is_dir():
                messages = roots[0] / cand
                break
    if messages is None or not messages.is_dir():
        r.note("guards 2/3 skipped: messages directory not found (set it with --messages)")
        return files
    source = langs[0]
    src_file = messages / f"{source}.json"
    if not src_file.exists():
        r.err(f"guard 2 missing source language file {src_file}")
        return files
    src_keys = flatten(json.loads(src_file.read_text(encoding="utf-8")))
    for lang in langs[1:]:
        f = messages / f"{lang}.json"
        if not f.exists():
            r.err(f"guard 2 missing {f}")
            continue
        keys = flatten(json.loads(f.read_text(encoding="utf-8")))
        for k in sorted(src_keys - keys):
            r.err(f"guard 2 key \"{k}\" is missing the {lang} translation ({f})")
        for k in sorted(keys - src_keys):
            r.err(f"guard 2 {f} has orphan key \"{k}\"")
    for f in files:
        for m in WEB_KEY_CALLS.finditer(f.read_text(encoding="utf-8", errors="replace")):
            key = m.group(1)
            if key not in src_keys and not any(k.endswith("." + key) for k in src_keys):
                r.err(f"guard 3 {f} localization key \"{key}\" is not in {src_file}")
    return files


def main() -> int:
    p = argparse.ArgumentParser(description="Three localization guards")
    p.add_argument("--platform", required=True, choices=("apple", "android", "web"))
    p.add_argument("--root", required=True, help="component directory, such as Apple/Mac, Android, or Web")
    p.add_argument("--extra", action="append", default=[], help="additional directory to scan, such as Apple/Shared")
    p.add_argument("--langs", default="en", help="language list; the first is the source language")
    p.add_argument("--messages", help="Web: message JSON directory")
    p.add_argument("--min-files", type=int, default=1, help="minimum number of source files scanned")
    a = p.parse_args()

    roots = [Path(a.root)] + [Path(x) for x in a.extra]
    langs = [x.strip() for x in a.langs.split(",") if x.strip()]
    r = Report()
    if a.platform == "apple":
        files = apple_guards(roots, langs, r)
    elif a.platform == "android":
        files = android_guards(roots, langs, r)
    else:
        files = web_guards(roots, langs, Path(a.messages) if a.messages else None, r)

    if len(files) < a.min_files:
        r.err(f"scanned {len(files)} source files, fewer than --min-files {a.min_files}: path resolution may be broken")
    for n in r.notes:
        print(f"! {n}")
    for e in r.errors:
        print(f"✗ {e}")
    print(f"i18n-guard [{a.platform}] scanned {len(files)} files, {len(r.errors)} problems.")
    return 1 if r.errors else 0


if __name__ == "__main__":
    sys.exit(main())
