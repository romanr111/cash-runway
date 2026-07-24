#!/usr/bin/env python3
"""
Compare a Timeline screenshot against the approved visual reference.

Produces the deterministic-fixture overlay artifact required by the Timeline
self-QA go/no-go (docs/plans/timeline-redesign-self-qa.md sec. 5.4): a
side-by-side, a 50% blend, and an absolute-difference image. Uses Pillow only
(no ImageMagick).

Usage:
    Scripts/timeline-reference-overlay.py \
        --screenshot /path/to/qa-nearEqual-uk.png \
        [--reference docs/plans/assets/timeline-screen-reference.jpg] \
        [--out /tmp/timeline-overlay] \
        [--width 400]
"""
import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageOps
except ImportError:
    sys.exit("Pillow (PIL) is required: pip install Pillow")

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REFERENCE = REPO_ROOT / "docs/plans/assets/timeline-screen-reference.jpg"


def load_scaled(path: Path, width: int) -> Image.Image:
    img = Image.open(path).convert("RGB")
    height = round(img.height * (width / img.width))
    return img.resize((width, height), Image.LANCZOS)


def match_height(img: Image.Image, height: int) -> Image.Image:
    # Reference and screenshot differ slightly in aspect ratio (status/home-bar
    # chrome). Pad (not stretch) to a common height so overlays stay proportional.
    if img.height == height:
        return img
    return ImageOps.pad(img, (img.width, height), color=(255, 255, 255), centering=(0.5, 0.0))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot", required=True, type=Path)
    parser.add_argument("--reference", default=DEFAULT_REFERENCE, type=Path)
    parser.add_argument("--out", default=Path("/tmp/timeline-overlay"), type=Path)
    parser.add_argument("--width", default=400, type=int)
    args = parser.parse_args()

    for label, path in (("screenshot", args.screenshot), ("reference", args.reference)):
        if not path.is_file():
            sys.exit(f"{label} not found: {path}")

    args.out.mkdir(parents=True, exist_ok=True)

    shot = load_scaled(args.screenshot, args.width)
    ref = load_scaled(args.reference, args.width)
    height = max(shot.height, ref.height)
    shot = match_height(shot, height)
    ref = match_height(ref, height)

    # Side-by-side: reference | screenshot
    gap = 12
    side = Image.new("RGB", (args.width * 2 + gap, height), (255, 255, 255))
    side.paste(ref, (0, 0))
    side.paste(shot, (args.width + gap, 0))
    side_path = args.out / "side-by-side.png"
    side.save(side_path)

    # 50% blend
    blend = Image.blend(ref, shot, 0.5)
    blend_path = args.out / "blend.png"
    blend.save(blend_path)

    # Absolute difference (brighter = larger deviation)
    diff = ImageChops.difference(ref, shot)
    diff_path = args.out / "difference.png"
    diff.save(diff_path)

    bbox = diff.getbbox()
    print(f"reference:  {args.reference}")
    print(f"screenshot: {args.screenshot}")
    print(f"side-by-side -> {side_path}")
    print(f"blend        -> {blend_path}")
    print(f"difference   -> {diff_path}")
    print(f"difference bbox (non-identical region): {bbox}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
