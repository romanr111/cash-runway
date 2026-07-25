#!/usr/bin/env python3
"""Generate Cash Runway release notes and version suggestion."""

import argparse
import os
import plistlib
import re
import subprocess
import sys
from collections import defaultdict


def run(cmd, **kwargs):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True, **kwargs).stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running {' '.join(cmd)}: {e.stderr.strip() or e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"Command not found: {cmd[0]}. Are you in a git repository?", file=sys.stderr)
        sys.exit(1)


def all_semver_tags():
    tags = run(["git", "tag", "--list", "--sort=-version:refname"]).splitlines()
    semver = re.compile(r"^v\d+\.\d+\.\d+$")
    return [t for t in tags if semver.match(t)]


def latest_tag(tags=None):
    if tags is None:
        tags = all_semver_tags()
    if not tags:
        return None
    return tags[0]


def suggest_next(tag):
    parts = tag[1:].split(".")
    major, minor, patch = map(int, parts)
    return f"v{major}.{minor}.{patch + 1}"


def suggest_build():
    """Return the build number from Info.plist, falling back to commit count."""
    plist_path = "AppHost/Info.plist"
    if os.path.isfile(plist_path):
        try:
            with open(plist_path, "rb") as f:
                plist = plistlib.load(f)
            build = plist.get("CFBundleVersion")
            if build is not None:
                return str(build)
        except Exception:
            pass
    return run(["git", "rev-list", "--count", "HEAD"]).strip()


def commits_since(tag, include_merges=False):
    args = ["git", "log", "--oneline", f"{tag}..HEAD"]
    if not include_merges:
        args.append("--no-merges")
    out = run(args).strip()
    return out.splitlines() if out else []


def categorize(lines):
    groups = defaultdict(list)
    for line in lines:
        lower = line.lower()
        # Strip leading hash/sha and whitespace for prefix checks
        text = re.sub(r"^[a-f0-9]+\s+", "", lower)
        if text.startswith("fix") or "fix(" in text.split(":", 1)[0]:
            groups["Fixes"].append(line)
        elif text.startswith("feat") or text.startswith("add") or "feat(" in text.split(":", 1)[0]:
            groups["Features"].append(line)
        elif text.startswith("refactor") or "refactor(" in text.split(":", 1)[0]:
            groups["Refactoring"].append(line)
        elif text.startswith("chore") or text.startswith("docs") or text.startswith("style") or text.startswith("test"):
            groups["Internal"].append(line)
        else:
            groups["Other"].append(line)
    return groups


def main():
    parser = argparse.ArgumentParser(description="Generate Cash Runway release notes")
    parser.add_argument("--tag", help="Last release tag (auto-detected if omitted)")
    parser.add_argument("--version", help="Target version for the release notes")
    parser.add_argument("--build", help="Build number (defaults to total commit count)")
    parser.add_argument("--output", "-o", help="Write release notes to file")
    args = parser.parse_args()

    tag = args.tag or latest_tag()
    if not tag:
        print("No semver tag found.", file=sys.stderr)
        sys.exit(1)

    lines = commits_since(tag)

    # If the tag is too recent (just created), walk back to the previous tag
    all_tags = all_semver_tags()
    if not lines and len(all_tags) > 1:
        fallback_tag = all_tags[1]
        print(f"No commits since {tag}; falling back to {fallback_tag}", file=sys.stderr)
        tag = fallback_tag
        lines = commits_since(tag)

    next_version = suggest_next(tag)
    version = args.version or next_version
    build = args.build or suggest_build()

    groups = categorize(lines)

    out = [f"## Release {version}\n", f"_Changes since {tag}_\n"]
    for heading in ["Features", "Fixes", "Refactoring", "Internal", "Other"]:
        items = groups.get(heading)
        if not items:
            continue
        out.append(f"### {heading}\n")
        for item in items:
            out.append(f"- {item}\n")
        out.append("\n")

    out.append("### SideStore\n")
    out.append(
        f"Trigger after merge: `gh workflow run sidestore-release.yml -f version={version.lstrip('v')} -f build={build}`\n"
    )
    out.append("\n### Manual gates\n")
    out.append("- [ ] Physical-device rehearsal completed\n")

    body = "".join(out)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(body)
        print(f"Wrote release notes to {args.output}")
    else:
        print(body)

    print(f"Latest tag: {tag}", file=sys.stderr)
    print(f"Suggested next version: {next_version}", file=sys.stderr)
    print(f"Suggested build number: {build}", file=sys.stderr)


if __name__ == "__main__":
    main()
