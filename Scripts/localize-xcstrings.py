#!/usr/bin/env python3
"""
Patch AppHost/Localizable.xcstrings with new or updated translations.

Usage:
    Scripts/localize-xcstrings.py <path-to-xcstrings> <path-to-strings.json>

strings.json format:
    {
        "Hello": "Привіт",
        "You have %d messages": "У вас %d повідомлень"
    }

The English key is used as the source value; the provided value is the Ukrainian
translation. Existing entries are updated, new entries are added.

This script performs text-level edits so it preserves Xcode's formatting and
produces minimal diffs.
"""
import json
import re
import sys
from pathlib import Path


def find_key_block(text: str, key: str) -> tuple[int, int] | None:
    """Return (start, end) indices of the JSON object value for `key`."""
    escaped = re.escape(json.dumps(key, ensure_ascii=False).strip('"'))
    # Match "key" : { with optional whitespace around colon.
    pattern = rf'"{escaped}"\s*:\s*\{{'
    match = re.search(pattern, text)
    if not match:
        return None

    start = match.end() - 1  # position of the opening brace
    brace_count = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        char = text[i]
        if escape:
            escape = False
            continue
        if char == "\\":
            escape = True
            continue
        if char == '"' and not in_string:
            in_string = True
            continue
        if char == '"' and in_string:
            in_string = False
            continue
        if in_string:
            continue
        if char == "{":
            brace_count += 1
        elif char == "}":
            brace_count -= 1
            if brace_count == 0:
                return start, i + 1
    return None


def find_uk_value(text: str, block_start: int, block_end: int) -> tuple[int, int] | None:
    """Return (start, end) indices of the uk value string within a key block."""
    block = text[block_start:block_end]
    # Find "uk" key inside localizations
    uk_match = re.search(r'"uk"\s*:\s*\{', block)
    if not uk_match:
        return None

    uk_block_start = block_start + uk_match.end() - 1
    brace_count = 0
    in_string = False
    escape = False
    for i in range(uk_block_start, block_end):
        char = text[i]
        if escape:
            escape = False
            continue
        if char == "\\":
            escape = True
            continue
        if char == '"' and not in_string:
            in_string = True
            continue
        if char == '"' and in_string:
            in_string = False
            continue
        if in_string:
            continue
        if char == "{":
            brace_count += 1
        elif char == "}":
            brace_count -= 1
            if brace_count == 0:
                break

    uk_block_end = i
    # Find the last "value" : "..." inside the uk block
    value_match = None
    for m in re.finditer(r'"value"\s*:\s*"', text[uk_block_start:uk_block_end]):
        value_match = m
    if not value_match:
        return None

    value_start = uk_block_start + value_match.end()
    # Find closing quote of the value string
    j = value_start
    while j < uk_block_end:
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            return value_start, j
        j += 1
    return None


def make_unit(key: str, value: str) -> str:
    return (
        f'\n    "{key}": {{'
        f'\n      "localizations": {{'
        f'\n        "en": {{'
        f'\n          "stringUnit": {{'
        f'\n            "state": "translated",'
        f'\n            "value": {json.dumps(key, ensure_ascii=False)}'
        f'\n          }}'
        f'\n        }},'
        f'\n        "uk": {{'
        f'\n          "stringUnit": {{'
        f'\n            "state": "translated",'
        f'\n            "value": {json.dumps(value, ensure_ascii=False)}'
        f'\n          }}'
        f'\n        }}'
        f'\n      }}'
        f'\n    }},'
    )


def patch_catalog_text(text: str, updates: dict[str, str]) -> tuple[str, list[str], list[str]]:
    catalog = json.loads(text)
    strings = catalog["strings"]

    added: list[str] = []
    changed: list[str] = []

    for key, uk_value in updates.items():
        if key in strings:
            block = find_key_block(text, key)
            if block is None:
                raise RuntimeError(f"Key {key!r} exists in parsed catalog but block not found in text")
            block_start, block_end = block
            value_range = find_uk_value(text, block_start, block_end)
            if value_range is None:
                # Key exists but has no uk localization. Insert uk block.
                uk_block = (
                    f'\n        "uk" : {{'
                    f'\n          "stringUnit" : {{'
                    f'\n            "state" : "translated",'
                    f'\n            "value" : {json.dumps(uk_value, ensure_ascii=False)}'
                    f'\n          }}'
                    f'\n        }}'
                )
                # Insert before the closing brace of the key block.
                insert_pos = block_end - 1
                # Add a comma if localizations block exists and uk is the first new localization.
                # Heuristic: if the character before the closing brace is a newline, insert directly.
                text = text[:insert_pos] + uk_block + text[insert_pos:]
                changed.append(key)
            else:
                value_start, value_end = value_range
                old_value = text[value_start:value_end]
                escaped_value = json.dumps(uk_value, ensure_ascii=False)[1:-1]
                if old_value == escaped_value:
                    continue
                text = text[:value_start] + escaped_value + text[value_end:]
                changed.append(key)
        else:
            added.append(key)
            # Insert new key near the top of the strings object.
            strings_open = text.find('"strings"')
            if strings_open == -1:
                raise RuntimeError('"strings" object not found')
            brace_match = re.search(r'"strings"\s*:\s*\{', text[strings_open:])
            if brace_match is None:
                raise RuntimeError('"strings" object opening brace not found')
            insert_pos = strings_open + brace_match.end()
            new_entry = make_unit(key, uk_value)
            text = text[:insert_pos] + new_entry + text[insert_pos:]

    return text, added, changed


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <xcstrings> <strings.json>", file=sys.stderr)
        return 1

    catalog_path = Path(sys.argv[1])
    updates_path = Path(sys.argv[2])

    if not catalog_path.exists():
        print(f"Catalog not found: {catalog_path}", file=sys.stderr)
        return 1
    if not updates_path.exists():
        print(f"Updates file not found: {updates_path}", file=sys.stderr)
        return 1

    with updates_path.open("r", encoding="utf-8") as f:
        updates = json.load(f)

    with catalog_path.open("r", encoding="utf-8") as f:
        original_text = f.read()

    new_text, added, changed = patch_catalog_text(original_text, updates)

    with catalog_path.open("w", encoding="utf-8") as f:
        f.write(new_text)

    if added:
        print(f"Added {len(added)} keys: {', '.join(added)}")
    if changed:
        print(f"Updated {len(changed)} keys: {', '.join(changed)}")
    if not added and not changed:
        print("No changes.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
