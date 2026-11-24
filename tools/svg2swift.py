#!/usr/bin/env python3
"""Convert the Synapse V4 Pro lighting SVG into native SwiftUI path data.

Output: app/Sources/Basilisk/Art/MouseArtwork.swift with one ArtShape per SVG element,
normalised to absolute M/L/C/Z commands with transforms baked in, tagged by layer
(body / LED zones / selection outlines / button faces) so the app can recolour and hit-test them.
"""
import re, sys, xml.etree.ElementTree as ET

src, out = sys.argv[1], sys.argv[2]
raw = open(src, encoding="utf-8").read()
NS = "{http://www.w3.org/2000/svg}"

# ---- CSS classes -------------------------------------------------------
css = {}
style = re.search(r"<style[^>]*>(.*?)</style>", raw, re.S)
if style:
    for m in re.finditer(r"([^{}]+)\{([^}]*)\}", style.group(1)):
        props = {}
        for p in m.group(2).split(";"):
            if ":" in p:
                k, v = p.split(":", 1); props[k.strip()] = v.strip()
        for sel in m.group(1).split(","):
            sel = sel.strip()
            if sel.startswith("."):
                css.setdefault(sel[1:], {}).update(props)

def resolve(el):
    st = {}
    for c in (el.get("class") or "").split():
        st.update(css.get(c, {}))
    for k in ("fill", "stroke", "stroke-width", "opacity", "fill-opacity", "display"):
        if el.get(k): st[k] = el.get(k)
    if el.get("style"):
        for p in el.get("style").split(";"):
            if ":" in p:
                k, v = p.split(":", 1); st[k.strip()] = v.strip()
    return st

def color(v):
    if not v or v == "none": return None
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 3: h = "".join(c * 2 for c in h)
        return int(h[:6], 16)
    return None

# ---- geometry ----------------------------------------------------------
def matrix(el):
    t = el.get("transform")
    if not t: return None
    m = re.match(r"matrix\(([^)]+)\)", t)
    return [float(x) for x in re.split(r"[\s,]+", m.group(1).strip())]

def apply(M, x, y):
    if not M: return x, y
    a, b, c, d, e, f = M
    return a * x + c * y + e, b * x + d * y + f

NUM = r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"

def parse_d(d):
    toks = re.findall(r"[MmLlHhVvCcSsQqZz]|" + NUM, d)
    ops, i, cmd = [], 0, None
    x = y = sx = sy = 0.0
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]; i += 1
            if cmd in "Zz":
                ops.append(("Z",)); x, y = sx, sy; continue
        rel = cmd.islower(); C = cmd.upper()
        if C == "M":
            nx, ny = num(), num()
            if rel: nx += x; ny += y
            x, y, sx, sy = nx, ny, nx, ny; ops.append(("M", x, y))
            cmd = "l" if rel else "L"
        elif C == "L":
            nx, ny = num(), num()
            if rel: nx += x; ny += y
            x, y = nx, ny; ops.append(("L", x, y))
        elif C == "H":
            nx = num(); x = nx + x if rel else nx; ops.append(("L", x, y))
        elif C == "V":
            ny = num(); y = ny + y if rel else ny; ops.append(("L", x, y))
        elif C == "C":
            p = [num() for _ in range(6)]
            if rel: p = [p[0]+x, p[1]+y, p[2]+x, p[3]+y, p[4]+x, p[5]+y]
            ops.append(("C", *p)); x, y = p[4], p[5]
        else:
            raise SystemExit(f"unsupported path command {cmd}")
    return ops

def shape_ops(el, tag):
    M = matrix(el)
    if tag == "path":
        ops = parse_d(el.get("d"))
    elif tag in ("polygon", "polyline"):
        pts = [float(v) for v in re.findall(NUM, el.get("points"))]
        pairs = list(zip(pts[0::2], pts[1::2]))
        ops = [("M", *pairs[0])] + [("L", *p) for p in pairs[1:]] + ([("Z",)] if tag == "polygon" else [])
    elif tag == "rect":
        x, y = float(el.get("x", 0)), float(el.get("y", 0))
        w, h = float(el.get("width")), float(el.get("height"))
        ops = [("M", x, y), ("L", x + w, y), ("L", x + w, y + h), ("L", x, y + h), ("Z",)]
    else:
        return None
    if M:
        t = []
        for op in ops:
            if op[0] == "Z": t.append(op); continue
            pts = list(op[1:]); np_ = []
            for k in range(0, len(pts), 2):
                np_ += apply(M, pts[k], pts[k + 1])
            t.append((op[0], *np_))
        ops = t
    return ops

def bbox(ops):
    xs, ys = [], []
    for op in ops:
        if op[0] != "Z":
            xs += op[1::2]; ys += op[2::2]
    return min(xs), min(ys), max(xs), max(ys)

def fmt(ops):
    parts = []
    for op in ops:
        if op[0] == "Z": parts.append("Z")
        else: parts.append(op[0] + ",".join(f"{v:.2f}".rstrip("0").rstrip(".") for v in op[1:]))
    return "".join(parts)

# ---- walk --------------------------------------------------------------
root = ET.fromstring(raw)
shapes = []

def layer_for(groups, el_id, ops, el=None):
    g = set(groups)
    if "Buttons" in g:   # Basilisk's added layer: index = firmware button id
        return "button", int(el.get("data-button"))
    cy = (bbox(ops)[1] + bbox(ops)[3]) / 2
    if "Bottom_LED" in g or "Bottom_Selection" in g:
        kind = "underglowLED" if "Bottom_LED" in g else "underglowSelect"
        n = re.match(r"_x3(\d)_", el_id or "")
        return kind, int(n.group(1)) if n else 0
    if "Top_LED" in g or "Top_Selection" in g:
        zone = "wheel" if cy < 160 else "logo"
        return (zone + ("LED" if "Top_LED" in g else "Select")), 0
    return "body", 0

def walk(el, groups):
    tag = el.tag.replace(NS, "")
    if tag in ("defs", "style", "title"): return
    if tag == "g" or tag == "svg":
        gid = el.get("id")
        for c in el: walk(c, groups + ([gid] if gid else []))
        return
    ops = shape_ops(el, tag)
    if not ops: return
    st = resolve(el)
    if st.get("display") == "none": return
    layer, idx = layer_for(groups, el.get("id"), ops, el)
    fill = color(st.get("fill", "#000000" if tag != "path" or "fill" not in st else st.get("fill")))
    if st.get("fill") == "none": fill = None
    shapes.append(dict(layer=layer, index=idx, fill=fill, stroke=color(st.get("stroke")),
                       sw=float(st.get("stroke-width", "1") or 1) if st.get("stroke") not in (None, "none") else 0,
                       op=float(st.get("opacity", "1")), d=fmt(ops)))

walk(root, [])

# body first, then LEDs, then selection outlines (paint order)
order = {"body": 0}
shapes.sort(key=lambda s: order.get(s["layer"], 1 if s["layer"].endswith("LED") else (3 if s["layer"] == "button" else 2)))

def hx(v): return "nil" if v is None else f"0x{v:06X}"
lines = [
    "// GENERATED by tools/svg2swift.py from assets/mouse/basilisk_v4_pro_lighting.svg — do not edit by hand.",
    "// Artwork © Razer Inc. (extracted from Synapse for personal use).",
    "import CoreGraphics", "",
    "enum MouseArtwork {",
    "    static let canvas = CGSize(width: 200, height: 320)",
    "    static let shapes: [ArtShape] = [",
]
for s in shapes:
    lines.append(f'        ArtShape(layer: .{s["layer"]}, index: {s["index"]}, fill: {hx(s["fill"])}, '
                 f'stroke: {hx(s["stroke"])}, strokeWidth: {s["sw"]:g}, opacity: {s["op"]:g}, d: "{s["d"]}"),')
lines += ["    ]", "}", ""]
open(out, "w").write("\n".join(lines))
from collections import Counter
print(f"wrote {len(shapes)} shapes ->", out)
print(dict(Counter((s["layer"], s["index"]) for s in shapes)))
