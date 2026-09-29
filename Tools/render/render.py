"""Paints what the addon builds, from the mock client, to PNG.

    python3 Tools/render/render.py [scene ...] [--skin midnight] [--out DIR]
                                   [--font PATH] [--scale 2]

Scenes: main, empty, menu, emoji, settings, toast, popout.

Tools/render/snapshot.lua loads the real addon in the mock client, builds the
scene and writes every visible texture, font string and edit box text with its
resolved rectangle, colour, draw order and clipping. This file only paints
that list -- nothing is laid out here -- so what is on the picture is what the
addon made, down to the pixel grid. Text is measured with the real font files
on both sides, so a bubble is as wide as the game would make it.

It is a design tool, not a screenshot. The game's own art (class icons and the
like) is not in the repository and is drawn as a placeholder, fonts the game
ships are stood in for by metric-compatible ones, and the game world behind the
window is a flat gradient.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")
SCREEN_W, SCREEN_H = 1920, 1080

SYS = "/usr/share/fonts/truetype/"
# WoW font path -> (local file, horizontal scale). Arial Narrow is Arial set
# at about 82 % width; Liberation Sans is metric-compatible with Arial.
FONT_STANDINS = {
    "fonts\\arialn.ttf": (SYS + "liberation/LiberationSans-Regular.ttf", 0.82),
    "fonts\\frizqt__.ttf": (SYS + "dejavu/DejaVuSans.ttf", 0.92),
    "fonts\\frizqt___cyr.ttf": (SYS + "dejavu/DejaVuSans.ttf", 0.92),
}
CJK = SYS + "wqy/wqy-zenhei.ttc"


def font_file(wow_path):
    key = (wow_path or "").lower()
    if key in FONT_STANDINS:
        return FONT_STANDINS[key]
    prefix = "interface\\addons\\whatthewhisper\\"
    if key.startswith(prefix):
        local = os.path.join(ADDON, *wow_path[len(prefix):].split("\\"))
        if os.path.exists(local):
            return local, 1.0
    return FONT_STANDINS["fonts\\arialn.ttf"]


def font_paths_in_use(extra):
    paths = set(FONT_STANDINS)
    fonts_dir = os.path.join(ADDON, "Media", "Fonts")
    if os.path.isdir(fonts_dir):
        for name in os.listdir(fonts_dir):
            if name.lower().endswith((".ttf", ".otf")):
                paths.add("Interface\\AddOns\\WhatTheWhisper\\Media\\Fonts\\" + name)
    if extra:
        paths.add(extra)
    return paths


RANGES = [(32, 0x250), (0x370, 0x400), (0x400, 0x530), (0x1E00, 0x1F00),
          (0x2000, 0x2070), (0x2190, 0x2200), (0x2600, 0x2800)]


def write_metrics(path, extra_font):
    from fontTools.ttLib import TTFont
    lines = ["return { fonts = {"]
    for wow in sorted(font_paths_in_use(extra_font)):
        local, xscale = font_file(wow)
        font = TTFont(local, fontNumber=0)
        upm = font["head"].unitsPerEm
        cmap = font.getBestCmap()
        hmtx = font["hmtx"]
        adv = {}
        for lo, hi in RANGES:
            for cp in range(lo, hi):
                glyph = cmap.get(cp)
                if glyph:
                    adv[cp] = hmtx[glyph][0] / upm * xscale
        avg = sum(adv.get(c, 0) for c in range(97, 123)) / 26
        body = ",".join("[%d]=%.4f" % (cp, a) for cp, a in sorted(adv.items()))
        lines.append('[%s] = { avg = %.4f, %s },' % (lua_str(wow.lower()), avg, body))
    lines.append("} }")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\") + '"'


# --------------------------------------------------------------------------
# Painting
# --------------------------------------------------------------------------

_textures = {}


def texture(wow_path):
    if wow_path in _textures:
        return _textures[wow_path]
    img = None
    key = (wow_path or "").replace("/", "\\")
    prefix = "Interface\\AddOns\\WhatTheWhisper\\"
    if key.lower().startswith(prefix.lower()):
        base = os.path.join(ADDON, *key[len(prefix):].split("\\"))
        for ext in ("", ".tga", ".TGA", ".png", ".blp"):
            if os.path.exists(base + ext) and not (base + ext).endswith(".blp"):
                img = Image.open(base + ext).convert("RGBA")
                break
    _textures[wow_path] = img
    return img


def crop_coords(img, coord):
    l, r, t, b = coord
    w, h = img.size
    x0, x1 = sorted((l * w, r * w))
    y0, y1 = sorted((t * h, b * h))
    x0, y0 = max(0, int(round(x0))), max(0, int(round(y0)))
    x1, y1 = min(w, max(x0 + 1, int(round(x1)))), min(h, max(y0 + 1, int(round(y1))))
    piece = img.crop((x0, y0, x1, y1))
    if l > r:
        piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
    if t > b:
        piece = piece.transpose(Image.FLIP_TOP_BOTTOM)
    return piece


def to_px(rect, s):
    l, b, w, h = rect
    x0 = l * s
    y0 = (SCREEN_H - (b + h)) * s
    return x0, y0, (l + w) * s, (SCREEN_H - b) * s


def tint(img, rgba):
    if not rgba:
        return img
    r, g, b = rgba[0], rgba[1], rgba[2]
    a = rgba[3] if len(rgba) > 3 and rgba[3] is not None else 1
    if (r, g, b, a) == (1, 1, 1, 1):
        return img
    ch = img.split()
    ch = [ch[0].point(lambda v: v * r), ch[1].point(lambda v: v * g),
          ch[2].point(lambda v: v * b), ch[3].point(lambda v: v * a)]
    return Image.merge("RGBA", ch)


def with_alpha(img, alpha):
    if alpha >= 0.999:
        return img
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: v * alpha)))


def paste(canvas, img, box, clip, s, add=False):
    x0, y0 = int(round(box[0])), int(round(box[1]))
    if clip:
        cx0, cy0, cx1, cy1 = to_px((clip[0], clip[1], clip[2] - clip[0], clip[3] - clip[1]), s)
        cx0, cy0, cx1, cy1 = [int(round(v)) for v in (cx0, cy0, cx1, cy1)]
        w, h = img.size
        lx, ly = max(0, cx0 - x0), max(0, cy0 - y0)
        rx, ry = min(w, cx1 - x0), min(h, cy1 - y0)
        if rx <= lx or ry <= ly:
            return
        img = img.crop((lx, ly, rx, ry))
        x0, y0 = x0 + lx, y0 + ly
    if add:
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        layer.paste(img, (x0, y0))
        from PIL import ImageChops
        premult = ImageChops.multiply(layer.convert("RGB"),
                                      Image.merge("RGB", [layer.split()[3]] * 3))
        base = canvas.convert("RGB")
        canvas.paste(Image.merge("RGBA", (*ImageChops.add(base, premult).split(),
                                          canvas.split()[3])))
        return
    cw, ch = canvas.size
    sx, sy = max(0, -x0), max(0, -y0)
    if sx >= img.size[0] or sy >= img.size[1] or x0 >= cw or y0 >= ch:
        return
    img = img.crop((sx, sy, min(img.size[0], cw - max(0, x0) + sx),
                    min(img.size[1], ch - max(0, y0) + sy)))
    canvas.alpha_composite(img, (max(0, x0), max(0, y0)))


def paint_texture(canvas, item, s):
    # Edges are rounded, not position and size separately: two pieces that
    # share an edge in the layout must share it on the canvas too.
    x0, y0, x1, y1 = [int(round(v)) for v in to_px(item["rect"], s)]
    w, h = max(1, x1 - x0), max(1, y1 - y0)
    if item.get("tex"):
        src = texture(item["tex"])
        if src is None:
            # The game's own art: a neutral placeholder the size of the art.
            img = Image.new("RGBA", (w, h), (120, 120, 128, 255))
        else:
            img = crop_coords(src, item.get("coord") or [0, 1, 0, 1]).resize((w, h), Image.LANCZOS)
    else:
        c = item.get("color") or [1, 1, 1, 1]
        a = c[3] if len(c) > 3 and c[3] is not None else 1
        img = Image.new("RGBA", (w, h), tuple(int(round(v * 255)) for v in (c[0], c[1], c[2], a)))
    grad = item.get("gradient")
    if grad:
        orient, ca, cb = grad
        gimg = Image.new("RGBA", (w, h))
        px = gimg.load()
        for yy in range(h):
            for xx in range(w):
                t = (xx / max(1, w - 1)) if orient == "HORIZONTAL" else (1 - yy / max(1, h - 1))
                px[xx, yy] = tuple(int(round((ca[i] + (cb[i] - ca[i]) * t) * 255)) for i in range(4))
        from PIL import ImageChops
        img = ImageChops.multiply(img, gimg)
    img = tint(img, item.get("vertex"))
    for mask in item.get("masks") or []:
        msrc = texture(mask.get("tex")) if mask.get("tex") else None
        if msrc is None:
            continue
        mx0, my0, mx1, my1 = to_px(mask["rect"], s)
        mw, mh = max(1, int(round(mx1 - mx0))), max(1, int(round(my1 - my0)))
        mimg = crop_coords(msrc, mask.get("coord") or [0, 1, 0, 1]).resize((mw, mh), Image.LANCZOS)
        full = Image.new("L", (w, h), 0)
        full.paste(mimg.split()[3], (int(round(mx0 - x0)), int(round(my0 - y0))))
        from PIL import ImageChops
        img.putalpha(ImageChops.multiply(img.split()[3], full))
    img = with_alpha(img, item["alpha"])
    paste(canvas, img, (x0, y0), item.get("clip"), s, add=(item.get("blend") == "ADD"))


_fonts = {}


def pil_font(wow_path, size, s):
    local, xscale = font_file(wow_path)
    key = (local, size, s)
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(local, max(1, int(round(size * s))))
        except OSError:
            _fonts[key] = ImageFont.truetype(FONT_STANDINS["fonts\\arialn.ttf"][0],
                                             max(1, int(round(size * s))))
    return _fonts[key], xscale


def needs_cjk(text):
    return any(0x2E80 <= ord(ch) <= 0x9FFF or 0xAC00 <= ord(ch) <= 0xD7AF for ch in text)


def parse_runs(text, base):
    """Splits WoW markup into runs of (kind, value, colour)."""
    runs, colour, i = [], base, 0
    stack = []
    out = ""
    while i < len(text):
        if text[i] == "|" and i + 1 < len(text):
            code = text[i + 1]
            if code == "c" and i + 10 <= len(text):
                if out:
                    runs.append(("text", out, colour))
                    out = ""
                hexa = text[i + 2:i + 10]
                stack.append(colour)
                colour = (int(hexa[2:4], 16) / 255, int(hexa[4:6], 16) / 255,
                          int(hexa[6:8], 16) / 255, int(hexa[0:2], 16) / 255)
                i += 10
                continue
            if code == "r":
                if out:
                    runs.append(("text", out, colour))
                    out = ""
                colour = stack.pop() if stack else base
                i += 2
                continue
            if code == "H":
                end = text.find("|h", i + 2)
                i = end + 2 if end >= 0 else i + 2
                continue
            if code == "h":
                i += 2
                continue
            if code == "T":
                end = text.find("|t", i + 2)
                if end >= 0:
                    if out:
                        runs.append(("text", out, colour))
                        out = ""
                    runs.append(("tex", text[i + 2:end], colour))
                    i = end + 2
                    continue
            if code == "A":
                end = text.find("|a", i + 2)
                i = end + 2 if end >= 0 else i + 2
                continue
            if code == "n":
                out += "\n"
                i += 2
                continue
            if code == "|":
                out += "|"
                i += 2
                continue
        out += text[i]
        i += 1
    if out:
        runs.append(("text", out, colour))
    return runs


def tex_spec(spec, size):
    parts = spec.split(":")
    path = parts[0]
    h = float(parts[1]) if len(parts) > 1 and parts[1] else 0
    w = float(parts[2]) if len(parts) > 2 and parts[2] else h
    h = h or size
    w = w or h
    coord = None
    if len(parts) >= 11:
        sw, sh = float(parts[5]), float(parts[6])
        l, r, t, b = (float(v) for v in parts[7:11])
        coord = [l / sw, r / sw, t / sh, b / sh]
    return path, w, h, coord


def layout_tokens(runs, size):
    """Breaks runs into words and spaces, each with its colour."""
    tokens = []
    for kind, value, colour in runs:
        if kind == "tex":
            tokens.append(("tex", value, colour))
            continue
        word = ""
        for ch in value:
            if ch in " \n":
                if word:
                    tokens.append(("word", word, colour))
                    word = ""
                tokens.append(("space" if ch == " " else "newline", ch, colour))
            else:
                word += ch
        if word:
            tokens.append(("word", word, colour))
    return tokens


def paint_text(canvas, item, s):
    size = item["size"]
    base = tuple(item["color"]) + ((1,) if len(item["color"]) < 4 else ())
    runs = parse_runs(item["text"], base)
    font, xscale = pil_font(item["font"], size, s)
    cjk_font = None

    def fnt(text):
        nonlocal cjk_font
        if needs_cjk(text):
            if cjk_font is None:
                cjk_font = ImageFont.truetype(CJK, max(1, int(round(size * s))))
            return cjk_font, 1.0
        return font, xscale

    def width(tok):
        kind, value, _ = tok
        if kind == "tex":
            _, w, _, _ = tex_spec(value, size)
            return w * s
        if kind == "newline":
            return 0
        f, xs = fnt(value)
        return f.getlength(value) * xs

    x0, y0, x1, y1 = to_px(item["rect"], s)
    insets = item.get("insets")
    if insets:
        x0 += insets[0] * s
        x1 -= insets[1] * s
        y0 += insets[2] * s
        y1 -= insets[3] * s
    box_w = x1 - x0
    tokens = layout_tokens(runs, size)
    lines, cur, cur_w = [], [], 0
    for tok in tokens:
        if tok[0] == "newline":
            lines.append(cur)
            cur, cur_w = [], 0
            continue
        w = width(tok)
        if item.get("wrap") and cur and tok[0] != "space" and cur_w + w > box_w + 0.5 * s:
            while cur and cur[-1][0] == "space":
                cur_w -= width(cur.pop())
            lines.append(cur)
            cur, cur_w = [], 0
        if tok[0] == "space" and not cur:
            continue
        cur.append(tok)
        cur_w += w
    lines.append(cur)

    line_h = (size + item.get("spacing", 0)) * s
    total_h = len(lines) * size * s + (len(lines) - 1) * item.get("spacing", 0) * s
    jv = item.get("justifyV", "MIDDLE")
    if jv == "TOP":
        top = y0
    elif jv == "BOTTOM":
        top = y1 - total_h
    else:
        top = y0 + ((y1 - y0) - total_h) / 2
    ascent, descent = font.getmetrics()
    baseline_frac = ascent / max(1, ascent + descent)

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for n, line in enumerate(lines):
        while line and line[-1][0] == "space":
            line = line[:-1]
        lw = sum(width(t) for t in line)
        jh = item.get("justifyH", "CENTER")
        if jh == "LEFT":
            x = x0
        elif jh == "RIGHT":
            x = x1 - lw
        else:
            x = x0 + (box_w - lw) / 2
        baseline = top + n * line_h + size * s * baseline_frac
        for tok in line:
            kind, value, colour = tok
            w = width(tok)
            if kind == "tex":
                path, tw, th, coord = tex_spec(value, size)
                src = texture(path)
                if src is not None:
                    img = crop_coords(src, coord or [0, 1, 0, 1]).resize(
                        (max(1, int(round(tw * s))), max(1, int(round(th * s)))), Image.LANCZOS)
                    cy = top + n * line_h + (size * s - th * s) / 2
                    layer.alpha_composite(img, (int(round(x)), max(0, int(round(cy)))))
            elif kind != "space":
                f, xs = fnt(value)
                fill = tuple(int(round(v * 255)) for v in (colour[0], colour[1], colour[2],
                                                            colour[3] if len(colour) > 3 else 1))
                if abs(xs - 1) < 1e-3:
                    draw.text((x, baseline), value, font=f, fill=fill, anchor="ls")
                else:
                    tw = int(f.getlength(value)) + 4
                    asc, desc = f.getmetrics()
                    tmp = Image.new("RGBA", (tw, asc + desc), (0, 0, 0, 0))
                    ImageDraw.Draw(tmp).text((0, asc), value, font=f, fill=fill, anchor="ls")
                    tmp = tmp.resize((max(1, int(round(tw * xs))), asc + desc), Image.LANCZOS)
                    layer.alpha_composite(tmp, (int(round(x)), max(0, int(round(baseline - asc)))))
            x += w
    if item["alpha"] < 0.999:
        layer = with_alpha(layer, item["alpha"])
    clip = item.get("clip")
    if clip:
        cx0, cy0, cx1, cy1 = to_px((clip[0], clip[1], clip[2] - clip[0], clip[3] - clip[1]), s)
        mask = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(mask).rectangle((cx0, cy0, cx1 - 1, cy1 - 1), fill=255)
        from PIL import ImageChops
        layer.putalpha(ImageChops.multiply(layer.split()[3], mask))
    canvas.alpha_composite(layer)


def backdrop(w, h):
    """A stand-in for the game world: dim, warm, a little uneven."""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = y / max(1, h - 1)
            u = x / max(1, w - 1)
            px[x, y] = (int(58 + 30 * u - 20 * t), int(66 + 18 * u - 16 * t), int(60 - 10 * t), 255)
    return img


def render(snapshot, out_path, s, crop=None):
    items = snapshot["items"]
    items.sort(key=lambda it: (it["strata"], it["level"], it["frame"], it["layer"],
                               it["sub"], it["order"]))
    canvas = backdrop(SCREEN_W * s // 4, SCREEN_H * s // 4).resize((SCREEN_W * s, SCREEN_H * s))
    for item in items:
        if item["kind"] == "tex":
            paint_texture(canvas, item, s)
        else:
            paint_text(canvas, item, s)
    if crop:
        canvas = canvas.crop(tuple(int(round(v)) for v in crop))
    canvas.convert("RGB").save(out_path)


def crop_for(snapshot, s, margin=36):
    focus = snapshot.get("focus")
    if focus:
        l, b, w, h = focus
    else:
        rects = [it["rect"] for it in snapshot["items"]
                 if it["rect"][2] < SCREEN_W * 0.9 and it["rect"][3] < SCREEN_H * 0.9]
        if not rects:
            return None
        l = min(r[0] for r in rects)
        b = min(r[1] for r in rects)
        w = max(r[0] + r[2] for r in rects) - l
        h = max(r[1] + r[3] for r in rects) - b
    x0, y0, x1, y1 = to_px((l - margin, b - margin, w + 2 * margin, h + 2 * margin), s)
    return (max(0, x0), max(0, y0), min(SCREEN_W * s, x1), min(SCREEN_H * s, y1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenes", nargs="*", default=["main"])
    ap.add_argument("--skin", default="midnight")
    ap.add_argument("--out", default=os.path.join(ROOT, "Tools", "render", "out"))
    ap.add_argument("--font", default=None, help="WoW font path to force")
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="wtw-render-")
    metrics = os.path.join(tmp, "metrics.lua")
    write_metrics(metrics, args.font)
    env = dict(os.environ)
    if args.font:
        env["WTW_FONT"] = args.font
    for scene in args.scenes:
        snap_path = os.path.join(tmp, scene + ".json")
        proc = subprocess.run(["lua5.1", os.path.join(ROOT, "Tools/render/snapshot.lua"),
                               scene, args.skin, snap_path, metrics],
                              cwd=ROOT, env=env, capture_output=True, text=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stdout + proc.stderr)
            sys.exit(proc.returncode)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        with open(snap_path) as fh:
            snapshot = json.load(fh)
        out = os.path.join(args.out, "%s-%s.png" % (scene, args.skin))
        render(snapshot, out, args.scale, crop_for(snapshot, args.scale))
        print(out)


if __name__ == "__main__":
    main()
