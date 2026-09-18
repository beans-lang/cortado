#!/usr/bin/env python3
"""Reads one control's parts out of its 4x capture: the pieces a bezel box
cannot show — a radio dot's diameter, a stepper chevron's run, where a field's
glyphs actually sit.

Everything here is a pixel measurement of the pinned native shots. Nothing is
inferred from a screenshot of our own renderer.

Geometry comes from the 4x shots, which resolve a quarter point. **Colours do
not.** A 4x capture blends its own edges, so the most common colour inside a
small shape can be one that is nowhere on screen; a flat interior pixel of the
2x shot is the colour the renderer has to match.
"""
import json, os, sys
import numpy as np
from PIL import Image

root = sys.argv[1] if len(sys.argv) > 1 else "build/reference"
shots = {s["file"]: s for s in json.load(open(os.path.join(root, "shots.json")))["shots"]}


def load(name):
    shot = shots[name]
    img = np.asarray(Image.open(os.path.join(root, "shots", name)).convert("RGBA")).astype(np.float64)
    return img, shot


def page_of(img):
    return img[1, 1].copy()


def mask_of(img, reference, tol=6.0):
    return np.abs(img - reference).max(axis=2) > tol


def box_of(mask):
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def pt(v, scale, origin=0.0):
    return round(v / scale - origin, 3)


def report(name, pairs):
    print(name.ljust(42) + "  ".join(f"{k}={v}" for k, v in pairs))


def parts(file):
    """Control box, plus the box of everything that differs from the control's
    own dominant fill — the mark, the dot, the glyphs."""
    img, shot = load(file)
    scale, pad = shot["scale"], shot["pad"]
    page = page_of(img)
    outer = box_of(mask_of(img, page))
    if outer is None:
        return None
    x0, y0, x1, y1 = outer
    inner = img[y0:y1 + 1, x0:x1 + 1]
    flat = inner.reshape(-1, 4)
    colours, counts = np.unique(flat, axis=0, return_counts=True)
    fill = colours[counts.argmax()]
    inside = mask_of(inner, fill, 24.0)
    mark = box_of(inside)
    return {
        "scale": scale, "pad": pad, "img": img, "shot": shot,
        "outer": outer, "fill": fill, "mark": mark,
        "box": (pt(x0, scale, pad), pt(y0, scale, pad), pt(x1 - x0 + 1, scale), pt(y1 - y0 + 1, scale)),
    }


def radio(size, appearance="light"):
    on = parts(f"radio_button_{size}_checked_{appearance}@4x.png")
    off = parts(f"radio_button_{size}_normal_{appearance}@4x.png")
    if on is None:
        return
    scale = on["scale"]
    x0, y0, x1, y1 = on["outer"]
    # the circle is the leftmost square block of the row; the title follows it
    height = y1 - y0 + 1
    circle = (x0, y0, x0 + height - 1, y1)
    sub = on["img"][y0:y1 + 1, x0:x0 + height]
    centre = sub[height // 2, height // 2]
    dot = box_of(np.abs(sub - centre).max(axis=2) <= 12.0)
    ring = "%02x%02x%02x%02x" % tuple(int(round(v)) for v in on["img"][y0 + height // 2, x0 + 1])
    offfill = "-"
    if off is not None:
        ox0, oy0, ox1, oy1 = off["outer"]
        h = oy1 - oy0 + 1
        offfill = "%02x%02x%02x%02x" % tuple(int(round(v)) for v in off["img"][oy0 + h // 2, ox0 + h // 2])
        offrim = "%02x%02x%02x%02x" % tuple(int(round(v)) for v in off["img"][oy0 + h // 2, ox0])
    else:
        offrim = "-"
    if dot:
        dx0, dy0, dx1, dy1 = dot
        report(f"radio {size}", [
            ("circle", f"{pt(height, scale)}"),
            ("dot", f"{pt(dx1 - dx0 + 1, scale)}x{pt(dy1 - dy0 + 1, scale)}"),
            ("dotLeft", pt(dx0, scale)), ("dotTop", pt(dy0, scale)),
            ("dotRight", pt(height - 1 - dx1, scale)), ("dotBottom", pt(height - 1 - dy1, scale)),
            ("onFill", "%02x%02x%02x%02x" % tuple(int(round(v)) for v in on["img"][y0 + 2, x0 + height // 2])),
            ("offFill", offfill), ("offRim", offrim), ("ring", ring)])


def glyph_run(file, band=None):
    """The ink box of the text in a control shot: everything that is neither the
    page nor the control's own fill."""
    p = parts(file)
    if p is None:
        return None
    img, scale, pad = p["img"], p["scale"], p["pad"]
    x0, y0, x1, y1 = p["outer"]
    sub = img[y0:y1 + 1, x0:x1 + 1]
    fill = p["fill"]
    ink = np.abs(sub - fill).max(axis=2) > 40.0
    if band:
        lo, hi = band
        keep = np.zeros_like(ink)
        keep[:, int(lo * scale):int(hi * scale)] = True
        ink = ink & keep
    b = box_of(ink)
    if b is None:
        return None
    gx0, gy0, gx1, gy1 = b
    return {
        "controlBox": p["box"],
        "inkLeft": pt(gx0, scale), "inkTop": pt(gy0, scale),
        "inkRight": pt(gx1 + 1, scale), "inkBottom": pt(gy1 + 1, scale),
        "inkW": pt(gx1 - gx0 + 1, scale), "inkH": pt(gy1 - gy0 + 1, scale),
    }


def field(size, control="text_field"):
    g = glyph_run(f"{control}_{size}_normal_light@4x.png")
    if not g:
        return
    report(f"{control} {size}", [("box", g["controlBox"]),
                                ("inkLeft", g["inkLeft"]), ("inkTop", g["inkTop"]),
                                ("inkBottom", g["inkBottom"]), ("inkH", g["inkH"])])


def stepper(size):
    p = parts(f"stepper_{size}_normal_light@4x.png")
    if p is None:
        return
    img, scale = p["img"], p["scale"]
    x0, y0, x1, y1 = p["outer"]
    sub = img[y0:y1 + 1, x0:x1 + 1]
    fill = p["fill"]
    ink = np.abs(sub - fill).max(axis=2) > 40.0
    h = ink.shape[0]
    top = box_of(ink[: h // 2])
    bottom = box_of(ink[h // 2:])
    rows = [i for i in range(h) if ink[i].sum() > ink.shape[1] * 0.6]
    report(f"stepper {size}", [
        ("box", p["box"]),
        ("upGlyph", None if not top else
            f"x{pt(top[0], scale)} y{pt(top[1], scale)} {pt(top[2]-top[0]+1, scale)}x{pt(top[3]-top[1]+1, scale)}"),
        ("downGlyph", None if not bottom else
            f"x{pt(bottom[0], scale)} y{pt(bottom[1] + h // 2, scale)} {pt(bottom[2]-bottom[0]+1, scale)}x{pt(bottom[3]-bottom[1]+1, scale)}"),
        ("dividerRows", [pt(r, scale) for r in rows])])


def switch(size, state="checked"):
    p = parts(f"switch_control_{size}_{state}_light@4x.png")
    if p is None:
        return
    img, scale = p["img"], p["scale"]
    x0, y0, x1, y1 = p["outer"]
    sub = img[y0:y1 + 1, x0:x1 + 1]
    mid = sub[sub.shape[0] // 2]
    track = mid[2]
    knob = box_of(np.abs(sub - track).max(axis=2) > 40.0)
    report(f"switch {size} {state}", [
        ("box", p["box"]),
        ("track", "%02x%02x%02x%02x" % tuple(int(round(v)) for v in track)),
        ("knob", None if not knob else
            f"x{pt(knob[0], scale)} y{pt(knob[1], scale)} {pt(knob[2]-knob[0]+1, scale)}x{pt(knob[3]-knob[1]+1, scale)}")])


def segmented(size):
    p = parts(f"segmented_{size}_normal_light@4x.png")
    if p is None:
        return
    img, scale = p["img"], p["scale"]
    x0, y0, x1, y1 = p["outer"]
    sub = img[y0:y1 + 1, x0:x1 + 1]
    row = sub[2]  # just under the top edge: dividers cross the whole height
    fill = p["fill"]
    band = sub[int(sub.shape[0] * 0.25):int(sub.shape[0] * 0.75)]
    column = np.abs(band - fill).max(axis=2).mean(axis=0)
    marks = [i for i in range(1, len(column) - 1)
             if column[i] > 8 and column[i] >= column[i - 1] and column[i] >= column[i + 1]]
    report(f"segmented {size}", [("box", p["box"]), ("dividerCols", [pt(m, scale) for m in marks][:12])])


def popup(size):
    p = parts(f"popup_button_{size}_normal_light@4x.png")
    if p is None:
        return
    img, scale = p["img"], p["scale"]
    x0, y0, x1, y1 = p["outer"]
    sub = img[y0:y1 + 1, x0:x1 + 1]
    fill = p["fill"]
    ink = np.abs(sub - fill).max(axis=2) > 40.0
    width = ink.shape[1]
    title = box_of(ink[:, : int(width * 0.7)])
    arrow = box_of(ink[:, int(width * 0.7):])
    report(f"popup {size}", [
        ("box", p["box"]),
        ("title", None if not title else
            f"x{pt(title[0], scale)} top{pt(title[1], scale)} bottom{pt(title[3]+1, scale)}"),
        ("chevrons", None if not arrow else
            f"x{pt(arrow[0] + int(width*0.7), scale)} y{pt(arrow[1], scale)} "
            f"{pt(arrow[2]-arrow[0]+1, scale)}x{pt(arrow[3]-arrow[1]+1, scale)}")])


def button(size):
    g = glyph_run(f"push_button_{size}_normal_light@4x.png")
    if not g:
        return
    report(f"push_button {size}", [("box", g["controlBox"]), ("inkLeft", g["inkLeft"]),
                                   ("inkTop", g["inkTop"]), ("inkBottom", g["inkBottom"])])


sizes = ["mini", "small", "regular", "large"]
for s in sizes: radio(s)
print()
for s in sizes: button(s)
print()
for s in sizes: popup(s)
print()
for s in sizes:
    for c in ("text_field", "search_field", "secure_field", "placeholder_field"): field(s, c)
print()
for s in sizes: stepper(s)
print()
for s in sizes:
    switch(s, "checked"); switch(s, "normal")
print()
for s in sizes: segmented(s)
