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
"""
import json
import sys
from pathlib import Path


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def patch_catalog(catalog_path: Path, updates: dict[str, str]) -> dict:
    with catalog_path.open("r", encoding="utf-8") as f:
        catalog = json.load(f)

    strings = catalog["strings"]
    changed: list[str] = []
    added: list[str] = []

    for key, uk_value in updates.items():
        if key not in strings:
            strings[key] = {"localizations": {}}
            added.append(key)
        else:
            changed.append(key)

        localizations = strings[key].setdefault("localizations", {})
        localizations["en"] = make_unit(key)
        localizations["uk"] = make_unit(uk_value)

    return catalog, added, changed


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

    catalog, added, changed = patch_catalog(catalog_path, updates)

    with catalog_path.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")

    if added:
        print(f"Added {len(added)} keys: {', '.join(added)}")
    if changed:
        print(f"Updated {len(changed)} keys: {', '.join(changed)}")
    if not added and not changed:
        print("No changes.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
