#!/usr/bin/env python3
"""Validate CashRunwayCore module wiring across Package.swift and the Xcode project.

The Xcode project (an OpenStep plist) is converted to XML with plutil and parsed
with plistlib, so every check reasons about the parsed object graph rather than
section markers, object IDs, or regex. The checks therefore survive project
regeneration and renaming of build-phase identifiers.

Checks:
  1. Package.swift declares the CashRunwayCore library product.
  2. The CashRunwayCoreTests target depends on the CashRunwayCore target.
  3. The Xcode project references the root local package (relativePath ".").
  4. The CashRunway app target links CashRunwayCore exactly once, from the root
     local package (not from a remote or vendored package).
  5. No Core source file is compiled into the app target's Sources build phase.
"""
from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "CashRunway.xcodeproj" / "project.pbxproj"
PACKAGE = REPO / "Package.swift"

APP_TARGET = "CashRunway"
APP_PRODUCT_TYPE = "com.apple.product-type.application"
CORE_PRODUCT = "CashRunwayCore"
CORE_TESTS_TARGET = "CashRunwayCoreTests"
CORE_SOURCE_PREFIX = "Sources/CashRunwayCore/"


def die(message: str) -> None:
    print(f"❌ {message}", file=sys.stderr)
    sys.exit(1)


def passed(message: str) -> None:
    print(f"✅ {message}")


def load_objects() -> dict:
    if not PROJECT.exists():
        die(f"project file not found: {PROJECT}")
    proc = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", str(PROJECT)],
        check=False,
        capture_output=True,
    )
    if proc.returncode != 0:
        die(
            "plutil could not parse "
            f"{PROJECT.name}:\n{proc.stderr.decode('utf-8', 'replace').strip()}"
        )
    try:
        pbx = plistlib.loads(proc.stdout)
    except Exception as exc:
        die(f"could not parse plist output: {exc}")
    objects = pbx.get("objects") if isinstance(pbx, dict) else None
    if not isinstance(objects, dict):
        die("project.pbxproj does not contain an 'objects' dictionary")
    return objects


def with_isa(objects: dict, isa: str) -> list[dict]:
    return [obj for obj in objects.values() if isinstance(obj, dict) and obj.get("isa") == isa]


def app_target(objects: dict) -> dict:
    targets = [
        obj
        for obj in with_isa(objects, "PBXNativeTarget")
        if obj.get("name") == APP_TARGET and obj.get("productType") == APP_PRODUCT_TYPE
    ]
    if not targets:
        die(f"no application native target named '{APP_TARGET}' found")
    return targets[0]


def phases(objects: dict, target: dict, isa: str) -> list[dict]:
    result = []
    for phase_id in target.get("buildPhases", []):
        phase = objects.get(phase_id)
        if isinstance(phase, dict) and phase.get("isa") == isa:
            result.append(phase)
    return result


def referenced_path(objects: dict, build_file: dict) -> str:
    """Resolve a PBXBuildFile's referenced path, expanding variant groups."""
    ref_id = build_file.get("fileRef") or build_file.get("productRef")
    ref = objects.get(ref_id) if ref_id else None
    if not isinstance(ref, dict):
        return ""
    if ref.get("isa") == "PBXVariantGroup":
        return " ".join(
            (objects.get(child_id) or {}).get("path", "")
            for child_id in ref.get("children", [])
        )
    return ref.get("path") or ref.get("name") or ""


def check_package_product() -> None:
    text = PACKAGE.read_text() if PACKAGE.exists() else ""
    if f'name: "{CORE_PRODUCT}"' not in text:
        die(f"{PACKAGE.name} does not declare a {CORE_PRODUCT} product")
    passed(f"{PACKAGE.name} declares the {CORE_PRODUCT} product")


def check_package_test_target() -> None:
    text = PACKAGE.read_text() if PACKAGE.exists() else ""
    start = text.find(f'name: "{CORE_TESTS_TARGET}"')
    if start == -1:
        die(f"{PACKAGE.name} does not declare a {CORE_TESTS_TARGET} target")
    # The dependencies array follows the target name; require Core there.
    if f'"{CORE_PRODUCT}"' not in text[start : start + 400]:
        die(f"{CORE_TESTS_TARGET} does not depend on the {CORE_PRODUCT} target")
    passed(f"{CORE_TESTS_TARGET} depends on the {CORE_PRODUCT} target")


def check_root_local_package(objects: dict) -> list:
    root_ids = [
        obj_id
        for obj_id, obj in objects.items()
        if isinstance(obj, dict)
        and obj.get("isa") == "XCLocalSwiftPackageReference"
        and obj.get("relativePath") == "."
    ]
    if not root_ids:
        die("Xcode project has no root local package reference (relativePath '.')")
    passed("Xcode project references the root local package (relativePath '.')")
    return root_ids


def check_core_link(objects: dict, root_package_ids: list) -> None:
    target = app_target(objects)
    link_phases = phases(objects, target, "PBXFrameworksBuildPhase")
    if not link_phases:
        die(f"{APP_TARGET} target has no Frameworks build phase")
    core_products = []
    for phase in link_phases:
        for build_file_id in phase.get("files", []):
            build_file = objects.get(build_file_id)
            if not isinstance(build_file, dict):
                continue
            product_ref = build_file.get("productRef")
            if not product_ref:
                continue
            dependency = objects.get(product_ref)
            if isinstance(dependency, dict) and dependency.get("productName") == CORE_PRODUCT:
                core_products.append(dependency)
    if not core_products:
        die(f"{APP_TARGET} target does not link {CORE_PRODUCT}")
    if len(core_products) > 1:
        die(
            f"{APP_TARGET} target links {CORE_PRODUCT} "
            f"{len(core_products)} times (expected 1)"
        )
    if core_products[0].get("package") not in root_package_ids:
        die(f"{CORE_PRODUCT} product dependency does not belong to the root local package")
    passed(f"{APP_TARGET} target links {CORE_PRODUCT} exactly once from the root package")


def check_no_core_sources_in_app(objects: dict) -> None:
    target = app_target(objects)
    source_phases = phases(objects, target, "PBXSourcesBuildPhase")
    if not source_phases:
        die(f"{APP_TARGET} target has no Sources build phase")
    offenders = []
    total = 0
    for phase in source_phases:
        for build_file_id in phase.get("files", []):
            build_file = objects.get(build_file_id)
            if not isinstance(build_file, dict):
                continue
            total += 1
            path = referenced_path(objects, build_file).replace("\\", "/")
            if CORE_SOURCE_PREFIX in path:
                offenders.append(path)
    if offenders:
        die(
            f"{APP_TARGET} Sources phase still compiles Core source(s): "
            f"{', '.join(sorted(set(offenders)))}"
        )
    passed(f"{APP_TARGET} Sources phase has no Core source files ({total} file(s) checked)")


def main() -> int:
    check_package_product()
    check_package_test_target()
    objects = load_objects()
    root_ids = check_root_local_package(objects)
    check_core_link(objects, root_ids)
    check_no_core_sources_in_app(objects)
    print()
    print("OK: CashRunwayCore module wiring is correct.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
