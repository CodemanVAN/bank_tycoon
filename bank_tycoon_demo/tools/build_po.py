#!/usr/bin/env python3
"""Merge localization fragment JSONs into merged locale JSONs and gettext .pot/.po files."""

from __future__ import annotations

import json
from pathlib import Path

LOCALES = ("zh_CN", "en", "ja")
MODULE_ORDER = ("core", "sim", "world", "hud", "panels")


def _escape_po(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r\n", "\n")
        .replace("\n", "\\n")
    )


def load_locale_fragments(loc_dir: Path, locale: str) -> dict[str, str]:
    merged: dict[str, str] = {}
    # Load ordered module fragments first
    for mod in MODULE_ORDER:
        frag = loc_dir / f"{mod}.{locale}.json"
        if frag.is_file():
            data = json.loads(frag.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                for k, v in data.items():
                    merged[str(k)] = str(v)

    # Also pick up any additional *.{locale}.json fragment files
    suffix = f".{locale}.json"
    for frag in sorted(loc_dir.glob(f"*{suffix}")):
        if frag.name in {f"{m}{suffix}" for m in MODULE_ORDER}:
            continue
        data = json.loads(frag.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            for k, v in data.items():
                merged[str(k)] = str(v)

    return merged


def build_pot(keys: list[str]) -> str:
    lines = [
        "# Starway Bank — Bank Tycoon Translation Template",
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: Starway Bank 0.1.0\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        "",
    ]
    for key in keys:
        esc_k = _escape_po(key)
        lines.append(f'msgid "{esc_k}"')
        lines.append('msgstr ""')
        lines.append("")
    return "\n".join(lines)


def build_po(locale: str, keys: list[str], table: dict[str, str], fallback_en: dict[str, str]) -> str:
    lines = [
        f"# Starway Bank — Bank Tycoon ({locale})",
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: Starway Bank 0.1.0\\n"',
        f'"Language: {locale}\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        "",
    ]
    for key in keys:
        val = table.get(key, fallback_en.get(key, key))
        esc_k = _escape_po(key)
        esc_v = _escape_po(val)
        lines.append(f'msgid "{esc_k}"')
        lines.append(f'msgstr "{esc_v}"')
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    repo_demo = Path(__file__).resolve().parent.parent
    loc_dir = repo_demo / "localization"
    loc_dir.mkdir(parents=True, exist_ok=True)

    tables: dict[str, dict[str, str]] = {}
    all_keys_set: set[str] = set()
    ordered_keys: list[str] = []

    for locale in LOCALES:
        tbl = load_locale_fragments(loc_dir, locale)
        tables[locale] = tbl
        for k in tbl.keys():
            if k not in all_keys_set:
                all_keys_set.add(k)
                ordered_keys.append(k)

    # Write merged JSON per locale
    for locale in LOCALES:
        out_json = loc_dir / f"{locale}.json"
        out_json.write_text(
            json.dumps(tables[locale], ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    # Write messages.pot and <locale>.po
    pot_path = loc_dir / "messages.pot"
    pot_path.write_text(build_pot(ordered_keys), encoding="utf-8")

    en_tbl = tables.get("en", {})
    for locale in LOCALES:
        po_path = loc_dir / f"{locale}.po"
        po_path.write_text(
            build_po(locale, ordered_keys, tables[locale], en_tbl),
            encoding="utf-8",
        )

    print(f"[build_po] Built {len(ordered_keys)} keys across {LOCALES} in {loc_dir}")


if __name__ == "__main__":
    main()
