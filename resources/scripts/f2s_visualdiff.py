#!/usr/bin/env python3
"""Pixel-diff a render against its Figma reference. Pillow only — no ImageMagick.

The previous visualdiff shelled out to `magick`/`compare`. ImageMagick is absent on most
machines, and on an earlier build that single missing binary is what turned pixel diffing off for
the entire project; verification fell back to prose and every spacing error survived.
Pillow installs with pip and is usually already present, so the check can actually run.

Usage:
  f2s_visualdiff.py --render r.png --reference ref.png --out diff.png [--max 2.0]

Exit 0 if mismatch% <= --max, else 1.
"""
import argparse
import sys

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("pillow missing — python3 -m pip install pillow (see f2s_env_check.sh)")

# Per-channel difference below this is invisible to a human and usually just antialiasing
# or subpixel text rendering. Counting it would make every diff fail and the gate would
# get ignored — a gate that cries wolf gets bypassed, which is worse than no gate.
CHANNEL_TOL = 12


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", required=True)
    ap.add_argument("--reference", required=True)
    ap.add_argument("--out", help="write a highlight image of differing pixels")
    ap.add_argument("--max", type=float, default=2.0, help="max mismatch %% allowed")
    ap.add_argument("--crop-reference", dest="crop_ref",
                    help="x,y,w,h box (pixels, reference image) to compare — use when the Figma "
                         "screenshot includes neighbouring sections or wave protrusions; say so in the verdict")
    ap.add_argument("--bg", help="hex colour to flatten transparent PNGs onto (default white), e.g. #fdf0f7")
    ap.add_argument("--crop-render", dest="crop_render",
                    help="x,y,w,h box (pixels, render image) to compare")
    a = ap.parse_args()

    def crop(img, box):
        if not box: return img
        x, y, w, h = [int(float(n)) for n in box.split(",")]
        return img.crop((x, y, x + w, y + h))

    def flat(img, bg=(255, 255, 255)):
        # a Figma export with a transparent background must not composite as BLACK (PIL's RGB convert):
        # flatten alpha onto white (pass --bg to match the page colour) before comparing
        if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
            img = img.convert("RGBA"); base = Image.new("RGBA", img.size, bg + (255,)); base.alpha_composite(img); return base.convert("RGB")
        return img.convert("RGB")
    bg = tuple(int(a.bg.lstrip("#")[i:i+2], 16) for i in (0, 2, 4)) if a.bg else (255, 255, 255)
    r = crop(flat(Image.open(a.render), bg), a.crop_render)
    f = crop(flat(Image.open(a.reference), bg), a.crop_ref)

    # Compare at a common size: a width mismatch is itself a finding, so report it rather
    # than silently rescaling and pretending the images were comparable.
    resized = False
    if r.size != f.size:
        resized = True
        target = (min(r.width, f.width), min(r.height, f.height))
        r = r.resize(target, Image.LANCZOS)
        f = f.resize(target, Image.LANCZOS)

    diff = ImageChops.difference(r, f)
    mono = diff.convert("L").point(lambda p: 255 if p > CHANNEL_TOL else 0)
    differing = sum(mono.histogram()[1:])
    total = mono.width * mono.height
    pct = 100.0 * differing / max(total, 1)

    if a.out:
        highlight = r.copy()
        red = Image.new("RGB", r.size, (255, 0, 0))
        highlight.paste(red, mask=mono)
        Image.blend(r, highlight, 0.6).save(a.out)

    ok = pct <= a.max
    print(f"mismatch: {pct:.2f}%  (limit {a.max}%)  "
          f"{differing:,}/{total:,} px  → {'PASS' if ok else 'FAIL'}"
          + ("  [SIZE MISMATCH — render and reference differ in dimensions; "
             "this alone usually means the wrong viewport or a layout overflow]" if resized else ""))
    if a.out:
        print(f"diff image: {a.out}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
