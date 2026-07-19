#!/usr/bin/env python3
"""Original pixel-art sprite generator for forge-office.

Every pixel is authored here — there are NO third-party assets and no license
attached to the output. This script IS the source of truth; the atlas PNG it
writes (dashboard/public/sprites.png) is a build artifact you can regenerate:

    python3 dashboard/sprites/forge_sprites.py

Atlas layout — native pixel res, one 24x32 cell per pose:
  rows    = the 10 forge agents, in ROSTER order (must match index.html)
  columns = poses, indexed by COL below:
    0 down_idle 1 down_walk 2 up_idle 3 up_walk 4 left_idle 5 left_walk
    6 right_idle 7 right_walk 8 sit_idle 9 sit_type
Left frames are the right frames mirrored, so the art is drawn once.
"""
from PIL import Image, ImageDraw, ImageFont
import os

CW, CH = 24, 32
HERE = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.normpath(os.path.join(HERE, "..", "public"))

COLS = ["down", "down_walk", "up", "up_walk", "left", "left_walk",
        "right", "right_walk", "sit", "sit_type"]

SKIN, SKIN_SH = "#e8b98c", "#cf9f74"
PANTS = "#31415e"
OUTLINE = (20, 22, 30, 255)

# id, label, shirt, hair, accessory, accent
ROSTER = [
    ("claude",               "Claude",    "#2fb3bd", "#2b2b33", "headset",   "#22d3ee"),
    ("forge-architect",      "Architect", "#e8c531", "#7a4a21", "hardhat",   "#f2a417"),
    ("forge-reviewer",       "Reviewer",  "#d43d3d", "#26221e", "magnifier", "#ffd35c"),
    ("forge-tester",         "Tester",    "#2ea043", "#e8c531", "flask",     "#8fe3a6"),
    ("forge-aligner",        "Aligner",   "#d29922", "#6b3f1d", "level",     "#5a86e0"),
    ("forge-failure-hunter", "Hunter",    "#b34038", "#1f1b18", "target",    "#ff6a5c"),
    ("forge-typer",          "Typer",     "#3b6fd4", "#3a2c1c", "glasses",   "#9fd0ff"),
    ("forge-commenter",      "Commenter", "#9a5bd4", "#c9762a", "quill",     "#e0b0ff"),
    ("forge-scout",          "Scout",     "#39c5cf", "#4a3620", "cap",       "#2ea043"),
    ("forge-archivist",      "Archivist", "#8b96a8", "#6d6d6d", "box",       "#c8a06a"),
]


def C(hex_):
    n = int(hex_[1:], 16)
    return ((n >> 16) & 255, (n >> 8) & 255, n & 255, 255)


def shade(hex_, amt):
    n = int(hex_[1:], 16)
    return (max(0, min(255, (n >> 16) + amt)),
            max(0, min(255, ((n >> 8) & 255) + amt)),
            max(0, min(255, (n & 255) + amt)), 255)


def px(d, x, y, w, h, c):
    if w > 0 and h > 0:
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=c)


def head_wear(d, shirt, hair, acc, accent, cx, top, back=False):
    """Headwear-type accessories (persist across all facings)."""
    ac = C(accent)
    if acc == "headset":
        px(d, cx - 6, top + 1, 1, 5, ac); px(d, cx + 5, top + 1, 1, 5, ac)
        px(d, cx - 6, top - 1, 12, 1, ac)
        if not back:
            px(d, cx - 6, top + 4, 2, 2, ac)
    elif acc == "hardhat":
        px(d, cx - 6, top - 3, 12, 3, ac); px(d, cx - 5, top - 4, 10, 1, ac)
    elif acc == "cap":
        px(d, cx - 5, top - 2, 10, 2, ac)
        if not back:
            px(d, cx + 4, top - 1, 4, 1, ac)


def hand_item(d, acc, accent, hx, hy):
    """Handheld items — only drawn on the front (down) pose to stay legible."""
    ac = C(accent)
    if acc == "magnifier":
        px(d, hx, hy, 3, 3, ac); px(d, hx + 1, hy + 1, 1, 1, (255, 255, 255, 220))
        px(d, hx + 2, hy + 3, 2, 2, OUTLINE)
    elif acc == "flask":
        px(d, hx, hy - 1, 3, 5, ac); px(d, hx + 1, hy - 2, 1, 1, ac)
        px(d, hx, hy + 2, 3, 2, shade("#8fe3a6", -30))
    elif acc == "level":
        px(d, hx - 1, hy + 1, 5, 2, ac); px(d, hx + 1, hy + 1, 1, 2, (255, 255, 0, 255))
    elif acc == "target":
        px(d, hx, hy, 4, 4, ac); px(d, hx + 1, hy + 1, 2, 2, (255, 255, 255, 230))
        px(d, hx + 2, hy + 2, 1, 1, OUTLINE)
    elif acc == "quill":
        for i in range(4):
            px(d, hx + i, hy - i, 1, 1, ac)
        px(d, hx - 1, hy + 1, 1, 3, (255, 255, 255, 230))
    elif acc == "box":
        px(d, hx, hy, 5, 4, ac); px(d, hx, hy, 5, 1, shade("#c8a06a", 25))
        px(d, hx + 2, hy, 1, 4, shade("#c8a06a", -40))


def cell(shirt, hair, acc, accent, pose):
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sh, hr = C(shirt), C(hair)
    sk, sk_sh, ac = C(SKIN), C(SKIN_SH), C(accent)
    cx = 12
    walk = pose.endswith("_walk")
    base = pose.replace("_walk", "")
    px(d, cx - 6, 30, 12, 2, (0, 0, 0, 55))          # ground shadow

    if base in ("down", "up"):
        # legs (swap on walk)
        lo = 1 if walk else 0
        px(d, cx - 4, 24, 3, 6 - lo, C(PANTS)); px(d, cx + 1, 24 + lo, 3, 6 - lo, C(PANTS))
        px(d, cx - 5, 30, 4, 2, OUTLINE); px(d, cx + 1, 30, 4, 2, OUTLINE)
        # torso
        px(d, cx - 5, 15, 10, 10, sh); px(d, cx - 5, 15, 10, 2, shade(shirt, 28))
        px(d, cx + 3, 17, 2, 8, shade(shirt, -26))
        # arms
        px(d, cx - 7, 16, 2, 7, sh); px(d, cx + 5, 16, 2, 7, sh)
        px(d, cx - 7, 22, 2, 2, sk); px(d, cx + 5, 22, 2, 2, sk)
        # neck + head
        px(d, cx - 2, 13, 4, 2, sk_sh)
        px(d, cx - 5, 5, 10, 9, sk); px(d, cx - 5, 5, 10, 1, shade(SKIN, 18))
        if base == "down":
            px(d, cx - 2, 15, 4, 2, ac)                # collar accent
            px(d, cx + 3, 7, 2, 6, sk_sh)
            px(d, cx - 3, 9, 2, 2, OUTLINE); px(d, cx + 1, 9, 2, 2, OUTLINE)
            px(d, cx - 3, 9, 1, 1, (255, 255, 255, 230)); px(d, cx + 1, 9, 1, 1, (255, 255, 255, 230))
            px(d, cx - 5, 4, 10, 3, hr)
            px(d, cx - 6, 5, 2, 5, hr); px(d, cx + 4, 5, 2, 4, hr)
            if acc == "glasses":
                px(d, cx - 4, 9, 3, 2, ac); px(d, cx + 1, 9, 3, 2, ac); px(d, cx - 1, 9, 1, 1, ac)
            hand_item(d, acc, accent, cx + 6, 20)
        else:  # up = back of the head, all hair, no face
            px(d, cx - 5, 4, 10, 7, hr); px(d, cx - 6, 5, 2, 6, hr); px(d, cx + 4, 5, 2, 6, hr)
        head_wear(d, shirt, hair, acc, accent, cx, 4, back=(base == "up"))

    elif base == "right":
        lo = 1 if walk else 0
        px(d, cx - 2, 24, 3, 6 - lo, C(PANTS)); px(d, cx + 1, 24 + lo, 3, 6, C(PANTS))
        px(d, cx - 2, 30, 5, 2, OUTLINE)
        px(d, cx - 3, 15, 8, 10, sh); px(d, cx - 3, 15, 8, 2, shade(shirt, 28))
        px(d, cx + 3, 16, 2, 8, sh); px(d, cx + 3, 22, 2, 2, sk)   # forward arm
        px(d, cx - 3, 13, 5, 2, sk_sh)                            # neck
        px(d, cx - 3, 5, 8, 9, sk); px(d, cx - 3, 5, 8, 1, shade(SKIN, 18))
        px(d, cx + 2, 9, 2, 2, OUTLINE)                           # one eye, forward
        px(d, cx - 3, 4, 8, 4, hr); px(d, cx - 4, 5, 2, 6, hr)    # hair back
        head_wear(d, shirt, hair, acc, accent, cx, 4)

    elif base.startswith("sit"):                                 # seated, back to viewer
        # ("sit" AND "sit_type" — replace("_walk") does not strip "_type", so
        # an equality check left the sit_type cell EMPTY: seated agents
        # blinked in and out every pose toggle)
        px(d, cx - 6, 22, 12, 4, (43, 47, 56, 255))              # chair back
        px(d, cx - 7, 23, 2, 6, (32, 36, 44, 255)); px(d, cx + 5, 23, 2, 6, (32, 36, 44, 255))
        typ = pose == "sit_type"
        px(d, cx - 6, 12, 12, 11, sh); px(d, cx - 6, 12, 12, 2, shade(shirt, 24))
        au = 1 if typ else 0
        px(d, cx - 8, 13 - au, 2, 7, sh); px(d, cx + 6, 13 - (0 if typ else au), 2, 7, sh)
        px(d, cx - 8, 19 - au, 2, 2, sk); px(d, cx + 6, 19, 2, 2, sk)
        px(d, cx - 5, 3, 10, 10, sk)                             # head from behind
        px(d, cx - 5, 3, 10, 7, hr); px(d, cx - 6, 5, 2, 6, hr); px(d, cx + 4, 5, 2, 6, hr)
        head_wear(d, shirt, hair, acc, accent, cx, 3, back=True)

    return img


def build_atlas():
    rows = len(ROSTER)
    atlas = Image.new("RGBA", (CW * len(COLS), CH * rows), (0, 0, 0, 0))
    for r, (id_, label, shirt, hair, acc, accent) in enumerate(ROSTER):
        for c, pose in enumerate(COLS):
            if pose.startswith("left"):
                src = cell(shirt, hair, acc, accent, pose.replace("left", "right"))
                im = src.transpose(Image.FLIP_LEFT_RIGHT)
            else:
                im = cell(shirt, hair, acc, accent, pose)
            atlas.paste(im, (c * CW, r * CH), im)
    os.makedirs(PUBLIC, exist_ok=True)
    out = os.path.join(PUBLIC, "sprites.png")
    atlas.save(out)
    return out, atlas


def build_preview(atlas):
    Z = 5
    show = ["down", "left", "right", "up", "sit", "sit_type"]
    idx = [COLS.index(s) for s in show]
    cell_w, cell_h = CW * Z * len(show) + 40, CH * Z + 20
    pad = 20
    sw = cell_w + pad * 2
    sh = len(ROSTER) * cell_h + pad * 2 + 46
    sheet = Image.new("RGBA", (sw, sh), C("#0b1120"))
    sd = ImageDraw.Draw(sheet)
    try:
        tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
        sf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    except Exception:
        tf = f = sf = ImageFont.load_default()
    sd.text((pad, 12), "forge-office — original agent sprite sheet", font=tf, fill=C("#e6edf6"))
    sd.text((pad + 150, cell_h * 0 + 0), "", font=sf, fill=C("#64748b"))
    for r, (id_, label, shirt, hair, acc, accent) in enumerate(ROSTER):
        y = pad + 46 + r * cell_h
        sd.rectangle([pad, y - 4, pad + cell_w, y + CH * Z + 6], fill=C("#0f1728"),
                     outline=C("#1e2a40"), width=1)
        sd.rectangle([pad + 6, y + 4, pad + 14, y + 12], fill=C(shirt))
        sd.text((pad + 20, y + 2), label, font=f, fill=C("#cbd5e6"))
        for j, ci in enumerate(idx):
            src = atlas.crop((ci * CW, r * CH, ci * CW + CW, r * CH + CH))
            big = src.resize((CW * Z, CH * Z), Image.NEAREST)
            sheet.alpha_composite(big, (pad + 90 + j * (CW * Z + 6), y - 2))
            if r == 0:
                sd.text((pad + 90 + j * (CW * Z + 6), y - 20), show[ci_label(ci)] if False else show[j],
                        font=sf, fill=C("#64748b"))
    out = os.path.join(HERE, "sprites-preview.png")
    sheet.save(out)
    return out


def ci_label(ci):
    return ci


if __name__ == "__main__":
    out, atlas = build_atlas()
    prev = build_preview(atlas)
    print("atlas :", out, atlas.size)
    print("preview:", prev)
