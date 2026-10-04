#!/usr/bin/env python3
"""Renders the generated retrospective CSV as a PNG table image.
Throwaway evidence tooling for PR 124 — not part of the PR."""
import csv
import sys
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
with open(src, newline="", encoding="utf-8") as f:
    rows = list(csv.reader(f))

MONO_CANDIDATES = [
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Monaco.ttf",
    "/System/Library/Fonts/SFNS.ttf",
]
font_path = next((p for p in MONO_CANDIDATES if __import__("os").path.exists(p)), None)

def load_font(size, bold=False):
    if font_path:
        try:
            return ImageFont.truetype(font_path, size=size, index=1 if bold else 0)
        except Exception:
            try:
                return ImageFont.truetype(font_path, size=size)
            except Exception:
                pass
    return ImageFont.load_default(size=size)

col_count = max(len(r) for r in rows)
PAD, ROW_H, HDR_H = 10, 26, 34
font = load_font(14, bold=False)
header_font = load_font(14, bold=True)
title_font = load_font(18, bold=True)

widths = [0] * col_count
for r in rows:
    for i, cell in enumerate(r):
        widths[i] = int(max(widths[i], font.getlength(cell)))

table_w = sum(widths) + PAD * 2 * col_count + 2
width = table_w + 40
height = 70 + HDR_H + ROW_H * (len(rows) - 1) + 30
img = Image.new("RGB", (int(width), int(height)), (250, 250, 250))
draw = ImageDraw.Draw(img)

draw.text((20, 16), "Cash Runway retrospective export — CSV rendered as image",
          fill=(30, 30, 30), font=title_font)
draw.text((20, 44), f"source: {src.split('/')[-1]}  |  rows: {len(rows)-1} data + 1 header  |  PR 124 evidence",
          fill=(90, 90, 90), font=load_font(12))

x0, y0 = 20, 70
# header band
draw.rectangle([x0, y0, x0 + int(table_w), y0 + HDR_H], fill=(219, 229, 241))
x = x0
for i, cell in enumerate(rows[0]):
    draw.text((x + PAD, y0 + 8), cell, fill=(20, 40, 80), font=header_font)
    x += int(widths[i]) + PAD * 2
# data rows
for ri, row in enumerate(rows[1:], start=1):
    y = y0 + HDR_H + ROW_H * (ri - 1)
    if ri % 2 == 0:
        draw.rectangle([x0, y, x0 + int(table_w), y + ROW_H], fill=(255, 255, 255))
    x = x0
    for i, cell in enumerate(row):
        color = (40, 40, 40)
        if i == 12:  # Approximate column
            color = (180, 90, 0) if cell == "yes" else (40, 40, 40)
        draw.text((x + PAD, y + 5), cell, fill=color, font=font)
        x += int(widths[i]) + PAD * 2
# grid lines
y = y0
for i in range(len(rows) + 1):
    yy = y0 + HDR_H + ROW_H * (i - 1) if i > 0 else y0
    draw.line([x0, yy, x0 + int(table_w), yy], fill=(180, 190, 200), width=1)
x = x0
for i in range(col_count):
    off = x + (int(widths[i]) + PAD * 2 if i < col_count else 0)
    x += int(widths[i]) + PAD * 2
    if i < col_count - 1:
        draw.line([x, y0, x, y0 + HDR_H + ROW_H * (len(rows) - 1)], fill=(180, 190, 200), width=1)
draw.line([x0, y0, x0, y0 + HDR_H + ROW_H * (len(rows) - 1)], fill=(180, 190, 200), width=1)
draw.line([x0 + int(table_w), y0, x0 + int(table_w), y0 + HDR_H + ROW_H * (len(rows) - 1)], fill=(180, 190, 200), width=1)

img.save(dst, "PNG")
print(f"WROTE {dst} size={img.size}")