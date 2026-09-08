"""Renders WhatTheWhisper's main window from the addon's real design tokens.

This is a design review tool, not a screenshot: it reads Core/Namespace.lua and
the skin files through Tools/dump_tokens.lua, so every spacing, size, radius and
colour here is the value the addon actually uses. If the mock-up looks wrong,
the addon looks wrong.
"""
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SCALE = 2
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

tokens = json.loads(subprocess.check_output(
    ["lua5.1", os.path.join(ROOT, "Tools/dump_tokens.lua")]).decode())
S, R, SZ, T = tokens["S"], tokens["R"], tokens["SZ"], tokens["T"]

icons = Image.open(os.path.join(ROOT, "Tools/preview/icons.png")).convert("RGBA")
emoji = Image.open(os.path.join(ROOT, "Tools/preview/emoji.png")).convert("RGBA")
ICON_NAMES = [n.strip() for n in subprocess.check_output(
    ["lua5.1", "-e",
     'local _,ns=nil,{} local f=assert(loadfile("%s/WhatTheWhisper/UI/IconAtlas.lua")) '
     'f("x",ns) local k={} for name in pairs(ns.ICON_ATLAS) do k[#k+1]=name end '
     'table.sort(k) print(table.concat(k,"\\n"))' % ROOT]).decode().split("\n") if n.strip()]
ICON_COORDS = json.loads(subprocess.check_output(
    ["lua5.1", "-e",
     'local ns={} local f=assert(loadfile("%s/WhatTheWhisper/UI/IconAtlas.lua")) f("x",ns) '
     'local out={} for name,c in pairs(ns.ICON_ATLAS) do out[#out+1]=string.format('
     '"\\"%%s\\":[%%f,%%f,%%f,%%f]",name,c[1],c[2],c[3],c[4]) end '
     'print("{"..table.concat(out,",").."}")' % ROOT]).decode())


def font(size, bold=False):
    return ImageFont.truetype(FONT_PATH, int(size * SCALE))


def rgba(c, alpha_scale=1.0):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(c[3] * 255 * alpha_scale))


class Canvas:
    """Draws in addon units; everything is multiplied by SCALE on the way out."""

    def __init__(self, w, h, bg):
        self.img = Image.new("RGBA", (int(w * SCALE), int(h * SCALE)), bg)
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def rrect(self, x, y, w, h, radius, fill=None, outline=None, width=1, corners=None):
        box = [x * SCALE, y * SCALE, (x + w) * SCALE - 1, (y + h) * SCALE - 1]
        # PIL degenerates when the radius reaches half the shorter side.
        r = max(0.0, min(radius, w / 2 - 1, h / 2 - 1)) * SCALE
        if corners is None:
            self.d.rounded_rectangle(box, radius=r, fill=fill, outline=outline,
                                     width=int(width * SCALE))
        else:
            self.d.rounded_rectangle(box, radius=r, fill=fill, outline=outline,
                                     width=int(width * SCALE), corners=corners)

    def rect(self, x, y, w, h, fill):
        self.d.rectangle([x * SCALE, y * SCALE, (x + w) * SCALE - 1, (y + h) * SCALE - 1], fill=fill)

    def hline(self, x, y, w, fill, thickness=1):
        self.d.rectangle([x * SCALE, y * SCALE, (x + w) * SCALE - 1,
                          y * SCALE + max(1, int(thickness * SCALE / 2)) - 1], fill=fill)

    def vline(self, x, y, h, fill, thickness=1):
        self.d.rectangle([x * SCALE, y * SCALE, x * SCALE + max(1, int(thickness * SCALE / 2)) - 1,
                          (y + h) * SCALE - 1], fill=fill)

    def circle(self, cx, cy, r, fill=None, outline=None, width=1):
        self.d.ellipse([(cx - r) * SCALE, (cy - r) * SCALE, (cx + r) * SCALE, (cy + r) * SCALE],
                       fill=fill, outline=outline, width=int(width * SCALE))

    def text(self, x, y, value, size, fill, anchor="lm", maxw=None):
        f = font(size)
        if maxw is not None:
            while value and self.d.textlength(value, font=f) > maxw * SCALE:
                value = value[:-1]
                if self.d.textlength(value + "...", font=f) <= maxw * SCALE:
                    value += "..."
                    break
        self.d.text((x * SCALE, y * SCALE), value, font=f, fill=fill, anchor=anchor)
        return self.d.textlength(value, font=f) / SCALE

    def measure(self, value, size):
        return self.d.textlength(value, font=font(size)) / SCALE

    def icon(self, name, x, y, size, color):
        coords = ICON_COORDS.get(name)
        if not coords:
            return
        u1, u2, v1, v2 = coords
        box = (int(u1 * 512), int(v1 * 512), int(u2 * 512), int(v2 * 512))
        glyph = icons.crop(box).resize((int(size * SCALE), int(size * SCALE)), Image.LANCZOS)
        tint = Image.new("RGBA", glyph.size, color)
        tint.putalpha(glyph.getchannel("A"))
        self.img.alpha_composite(tint, (int(x * SCALE), int(y * SCALE)))

    def emoji(self, name, x, y, size, index):
        col, row = index % 8, index // 8
        box = (col * 64, row * 64, col * 64 + 64, row * 64 + 64)
        glyph = emoji.crop(box).resize((int(size * SCALE), int(size * SCALE)), Image.LANCZOS)
        self.img.alpha_composite(glyph, (int(x * SCALE), int(y * SCALE)))


# --------------------------------------------------------------------------
# Sample content
# --------------------------------------------------------------------------

CONVERSATIONS = [
    dict(name="Thrall", cls=(0.00, 0.44, 0.87), preview="Yo kommst du Raid?",
         time="22:41", unread=2, selected=True, initial="T"),
    dict(name="Jaina Proudmoore", cls=(0.41, 0.80, 0.94), preview="You: Portal in 5 Minuten bitte",
         time="21:07", unread=0, initial="J"),
    dict(name="Sylvanas", cls=(1.00, 1.00, 1.00), preview="ok bin da", time="Mon",
         unread=0, muted=True, initial="S"),
    dict(name="Anduin", cls=(0.96, 0.55, 0.73), preview="Danke dir!", time="05.09.",
         unread=1, pinned=True, initial="A"),
    dict(name="Muradin", cls=(0.78, 0.61, 0.43), preview="bis morgen", time="03.09.",
         unread=0, initial="M"),
]

THREAD = [
    ("sep", "Today"),
    ("in", ["Yo kommst du Raid?", "wir brauchen noch einen Heiler"], "22:41"),
    ("out", ["Ja bin gleich da"], "22:42", "ok"),
    ("in", ["top", "invite ist raus"], "22:43"),
    ("out", ["Bin drin. Hab noch 2 Flasks ubrig, brauchst du eine?",
             "sag kurz Bescheid"], "22:45", "ok"),
    ("in", ["ja gerne :)"], "22:46"),
]


def render(skin_id, layout="hybrid", width=None, height=None, path=None):
    skin = tokens["skins"][skin_id]
    c = {k: rgba(v) for k, v in skin["colors"].items()}
    raw = skin["colors"]
    m = skin["metrics"]
    radius = lambda base: base * m.get("radiusScale", 1)

    def class_color(rgb, muted=False):
        blend = m.get("classColorBlend", 0)
        primary = raw["textPrimary"]
        out = [rgb[i] * (1 - blend) + primary[i] * blend for i in range(3)]
        if muted:
            mutedc = raw["textMuted"]
            out = [out[i] * 0.45 + mutedc[i] * 0.55 for i in range(3)]
        return tuple(int(v * 255) for v in out) + (255,)

    W = width or SZ["WINDOW_W"]
    H = height or SZ["WINDOW_H"]
    cv = Canvas(W, H, c["bg0"])

    sidebar_w = SZ["SIDEBAR_W"] if layout != "tabbed" else 0
    compact = sidebar_w and sidebar_w < SZ["SIDEBAR_COMPACT_AT"]
    title_h = SZ["TITLEBAR_H"]

    # window plate
    cv.rrect(0, 0, W, H, radius(R["LG"]), fill=c["bg0"], outline=c["borderSubtle"], width=1)

    # ---------------------------------------------------------------- titlebar
    cv.icon("logo", S["MD"] + 1, (title_h - 15) / 2, 15, c["accent"])
    x = S["MD"] + 1 + 15 + S["SM"]
    tw = cv.text(x, title_h / 2, "WhatTheWhisper", T["SMALL"], c["textSecondary"])
    badge_x = x + tw + S["SM"]
    badge_w = max(16, cv.measure("3", T["MICRO"]) + S["SM"] + 2)
    cv.rrect(badge_x, (title_h - 16) / 2, badge_w, 16, 8, fill=c["accent"])
    cv.text(badge_x + badge_w / 2, title_h / 2, "3", T["MICRO"], c["onAccent"], anchor="mm")

    bx = W - S["SM"] - 26
    for name in ("close", "minimize", "sliders", "grid"):
        cv.icon(name, bx + (26 - 13) / 2, (title_h - 13) / 2, 13, c["textSecondary"])
        bx -= 28
    cv.hline(0, title_h, W, c["borderSubtle"])

    # ----------------------------------------------------------------- sidebar
    if sidebar_w:
        cv.rect(0, title_h, sidebar_w, H - title_h, c["bg1"])
        head_h = SZ["SIDEBAR_HEADER_H"]
        if not compact:
            fh = 30
            fy = title_h + (head_h - fh) / 2
            cv.rrect(S["MD"], fy, sidebar_w - S["MD"] - S["XS"] - SZ["ICON_BTN"] - S["SM"], fh,
                     radius(R["MD"]), fill=c["inputBg"], outline=c["borderSubtle"], width=1)
            cv.icon("search", S["MD"] + S["MD"], fy + (fh - 14) / 2, 14, c["textMuted"])
            cv.text(S["MD"] + S["HUGE"], fy + fh / 2, "Search conversations", T["SMALL"],
                    c["textMuted"])
        # Filled: the sidebar's primary action, same weight as the send button.
        nc_x = sidebar_w - S["SM"] - SZ["ICON_BTN"]
        nc_y = title_h + (head_h - SZ["ICON_BTN"]) / 2
        cv.circle(nc_x + SZ["ICON_BTN"] / 2, nc_y + SZ["ICON_BTN"] / 2,
                  SZ["ICON_BTN"] / 2, fill=c["accent"])
        cv.icon("message_plus", nc_x + (SZ["ICON_BTN"] - 16) / 2,
                nc_y + (SZ["ICON_BTN"] - 16) / 2, 16, c["onAccent"])

        row_h = SZ["ROW_H"]
        y = title_h + head_h
        for conv in CONVERSATIONS:
            if y + row_h > H:
                break
            if conv.get("selected"):
                cv.rrect(S["SM"], y + 1, sidebar_w - S["SM"] * 2, row_h - 2,
                         radius(R["MD"]), fill=c["selected"])
                if m.get("accentBar", 1):
                    # Inside the row card, which is itself inset by S.SM -- the
                    # marker has to sit past that inset or it floats in the
                    # gutter and reads as the window edge.
                    bar_w = SZ["ACCENT_BAR_W"]
                    bar_x = S["SM"] + SZ["ACCENT_BAR_INSET"]
                    cv.rrect(bar_x, y + S["MD"], bar_w, row_h - S["MD"] * 2,
                             bar_w / 2, fill=c["accent"])

            av = SZ["AVATAR_LG"]
            ax, ay = S["LG"], y + (row_h - av) / 2
            cls = class_color(conv["cls"])
            cv.circle(ax + av / 2, ay + av / 2, av / 2, fill=cls)
            dark = sum(conv["cls"]) / 3 > 0.6
            cv.text(ax + av / 2, ay + av / 2 + 1, conv["initial"], T["BODY"],
                    (20, 23, 28, 255) if dark else (255, 255, 255, 240), anchor="mm")

            tx = S["LG"] + av + S["MD"]
            name_color = class_color(conv["cls"], muted=conv.get("muted", False))
            indicators = (15 if conv.get("pinned") else 0) + (16 if conv.get("muted") else 0)
            name_max = sidebar_w - tx - S["LG"] - 64 - S["SM"] - indicators
            nw = cv.text(tx, y + S["MD"] + 1 + T["BODY"] / 2, conv["name"], T["BODY"],
                         name_color, maxw=name_max)
            ix = tx + nw + S["XS"] + 1
            if conv.get("pinned"):
                cv.icon("pin_filled", ix, y + S["MD"] + 1, 10, c["textMuted"])
                ix += 14
            if conv.get("muted"):
                cv.icon("bell_off", ix, y + S["MD"], 11, c["textMuted"])

            unread = conv["unread"] > 0
            cv.text(sidebar_w - S["LG"], y + S["MD"] + 2 + T["MICRO"] / 2, conv["time"],
                    T["MICRO"], c["textSecondary"] if unread else c["textMuted"], anchor="rm")
            preview_max = sidebar_w - tx - S["LG"] - (30 if unread else 0)
            cv.text(tx, y + row_h - S["MD"] - 1 - T["SMALL"] / 2, conv["preview"], T["SMALL"],
                    c["textSecondary"] if unread else c["textMuted"], maxw=preview_max)
            if unread:
                bw = max(SZ["BADGE_H"], cv.measure(str(conv["unread"]), T["MICRO"]) + S["SM"] + 2)
                by = y + row_h - S["MD"] - SZ["BADGE_H"]
                fill = c["textMuted"] if conv.get("muted") else c["accent"]
                cv.rrect(sidebar_w - S["LG"] - bw, by, bw, SZ["BADGE_H"], SZ["BADGE_H"] / 2, fill=fill)
                cv.text(sidebar_w - S["LG"] - bw / 2, by + SZ["BADGE_H"] / 2,
                        str(conv["unread"]), T["MICRO"], c["onAccent"], anchor="mm")
            y += row_h
        cv.vline(sidebar_w, title_h, H - title_h, c["borderSubtle"])

    # -------------------------------------------------------------------- tabs
    content_x = sidebar_w
    content_w = W - content_x
    top = title_h
    if layout != "sidebar":
        tab_h = SZ["TAB_H"]
        cv.rect(content_x, top, content_w, tab_h, c["bg1"])
        tabs = [("Thrall", True, 0), ("Jaina", False, 2), ("Sylvanas", False, 0)]
        tw_each = min(SZ["TAB_MAX_W"], (content_w - S["XS"] * 2) / max(3, len(tabs)))
        tx = content_x + S["XS"]
        for index, (label, active, unread) in enumerate(tabs):
            # A divider between two resting tabs, dropped next to the active
            # one: without it the inactive tabs read as floating text.
            following = tabs[index + 1] if index + 1 < len(tabs) else None
            if not active and following is not None and not following[1]:
                cv.rect(tx + tw_each - 1, top + S["SM"], 1,
                        tab_h - S["SM"] * 2, c["borderSubtle"])
            if active:
                cv.rrect(tx, top, tw_each, tab_h, radius(R["MD"]), fill=c["bg2"],
                         corners=(True, True, False, False))
                # The raised fill alone is invisible in some skins; the accent
                # bar is what actually says which tab you are on.
                cv.rect(tx + radius(R["MD"]), top,
                        tw_each - radius(R["MD"]) * 2, SZ["ACCENT_BAR_W"], c["accent"])
            lx = tx + S["MD"]
            if unread:
                cv.circle(lx + 3, top + tab_h / 2, 3, fill=c["accent"])
                lx += 6 + S["SM"] - 1
            cv.text(lx, top + tab_h / 2, label, T["SMALL"],
                    c["textPrimary"] if active else c["textSecondary"],
                    maxw=tw_each - (lx - tx) - 18 - S["SM"])
            if active:
                cv.icon("close", tx + tw_each - S["SM"] - 13, top + (tab_h - 9) / 2, 9,
                        c["textMuted"])
            tx += tw_each
        cv.hline(content_x, top + tab_h, content_w, c["borderSubtle"])
        top += tab_h

    # ------------------------------------------------------------------ header
    head_h = SZ["HEADER_H"]
    cv.rect(content_x, top, content_w, head_h, c["headerBg"])
    av = SZ["AVATAR_MD"]
    ax = content_x + S["LG"]
    ay = top + (head_h - av) / 2
    thrall = class_color(CONVERSATIONS[0]["cls"])
    cv.circle(ax + av / 2, ay + av / 2, av / 2, fill=thrall)
    cv.text(ax + av / 2, ay + av / 2 + 1, "T", T["SMALL"], (255, 255, 255, 240), anchor="mm")
    cv.text(ax + av + S["MD"], top + head_h / 2 - 7, "Thrall", T["TITLE"], thrall)
    cv.text(ax + av + S["MD"], top + head_h / 2 + 9, "Level 70 · Shaman · Blackrock",
            T["MICRO"], c["textMuted"])
    hx = content_x + content_w - S["MD"] - SZ["ICON_BTN"]
    for name in ("dots", "popout", "search"):
        cv.icon(name, hx + (SZ["ICON_BTN"] - 16) / 2, top + (head_h - 16) / 2, 16,
                c["textSecondary"])
        hx -= SZ["ICON_BTN"] + S["XS"]
    cv.hline(content_x, top + head_h, content_w, c["borderSubtle"])

    # ------------------------------------------------------------------ canvas
    canvas_top = top + head_h
    composer_h = SZ["COMPOSER_MIN_H"]
    canvas_bottom = H - composer_h
    cv.rect(content_x, canvas_top, content_w, canvas_bottom - canvas_top, c["bg2"])

    pad = SZ["LIST_PAD_X"]
    avatar = SZ["AVATAR_SM"]
    gap = S["SM"]
    bubble_max = min(content_w * SZ["BUBBLE_MAX_PCT"], SZ["BUBBLE_MAX_ABS"],
                     content_w - pad * 2 - avatar - gap - SZ["SCROLLBAR_HIT"])
    content_max = bubble_max - SZ["BUBBLE_PAD_X"] * 2
    spacing = m.get("spacingScale", 1)
    bubble_radius = radius(m.get("bubbleRadius", R["LG"]))

    # Build the exact layout first, then place it so the newest message sits on
    # the composer -- same order of operations the addon uses.
    def wrap(line):
        rows, remaining = [], line
        while remaining:
            cut = len(remaining)
            while cut and cv.measure(remaining[:cut], T["BODY"]) > content_max:
                cut -= 1
            if cut < len(remaining):
                space = remaining.rfind(" ", 0, cut)
                if space > 0:
                    cut = space
            rows.append(remaining[:cut].strip())
            remaining = remaining[cut:].strip()
        return rows or [""]

    layout_items, total = [], SZ["LIST_PAD_Y"]
    for item in THREAD:
        if item[0] == "sep":
            total += SZ["MSG_GAP_DATE"] * spacing
            layout_items.append(dict(kind="sep", label=item[1], y=total, h=20))
            total += 20 + S["MD"] * spacing
            continue
        kind, lines, stamp = item[0], item[1], item[2]
        status = item[3] if len(item) > 3 else None
        total += SZ["MSG_GAP_GROUP"] * spacing
        layout_items.append(dict(kind="header", side=kind, stamp=stamp, y=total, h=18))
        total += 18 + 2
        for i, line in enumerate(lines):
            if i:
                total += SZ["MSG_GAP_TIGHT"]
            rows = wrap(line)
            widest = max(cv.measure(r, T["BODY"]) for r in rows)
            bh = (len(rows) * T["BODY"] + (len(rows) - 1) * tokens["LINE_SPACING"]
                  + SZ["BUBBLE_PAD_Y"] * 2)
            layout_items.append(dict(kind="bubble", side=kind, rows=rows, y=total, h=bh,
                                     w=min(widest, content_max) + SZ["BUBBLE_PAD_X"] * 2,
                                     first=i == 0, last=i == len(lines) - 1, status=status))
            total += bh
    total += SZ["LIST_PAD_Y"]

    # Short conversations rest on the composer instead of floating at the top.
    origin = min(canvas_top, canvas_bottom - total)
    if total < canvas_bottom - canvas_top:
        origin = canvas_bottom - total
    for it in layout_items:
        y = origin + it["y"]
        if y + it["h"] < canvas_top or y > canvas_bottom:
            continue
        if it["kind"] == "sep":
            lw = cv.measure(it["label"], T["MICRO"]) + S["MD"] * 2
            cx = content_x + (content_w - SZ["SCROLLBAR_HIT"]) / 2
            cv.rrect(cx - lw / 2, y, lw, it["h"], it["h"] / 2, fill=c["bg3"])
            cv.text(cx, y + it["h"] / 2, it["label"], T["MICRO"], c["textMuted"], anchor="mm")
        elif it["kind"] == "header":
            # A time and nothing else, on the side its group sits on. The name
            # is in the window header and the avatar is class coloured, so
            # repeating it over every group was pure noise.
            if it["side"] == "in":
                cv.text(content_x + pad + avatar + gap, y + 9, it["stamp"],
                        T["MICRO"], c["textMuted"])
            else:
                cv.text(content_x + content_w - pad - SZ["SCROLLBAR_HIT"], y + 9, it["stamp"],
                        T["MICRO"], c["textMuted"], anchor="rm")
        else:
            incoming = it["side"] == "in"
            bw, bh = it["w"], it["h"]
            if incoming:
                bx = content_x + pad + avatar + gap
                cv.rrect(bx, y, bw, bh, bubble_radius, fill=c["bubbleIn"],
                         corners=(not it["first"], True, True, True))
                if it["first"]:
                    cv.circle(content_x + pad + avatar / 2, y + avatar / 2, avatar / 2, fill=thrall)
                    cv.text(content_x + pad + avatar / 2, y + avatar / 2 + 1, "T",
                            T["MICRO"], (255, 255, 255, 235), anchor="mm")
                fill = c["bubbleInText"]
            else:
                bx = content_x + content_w - pad - SZ["SCROLLBAR_HIT"] - bw
                cv.rrect(bx, y, bw, bh, bubble_radius, fill=c["bubbleOut"],
                         corners=(True, not it["first"], True, True))
                fill = c["bubbleOutText"]
                if it["status"] and it["last"]:
                    cv.icon("check", bx - S["SM"] - 11, y + bh - 13, 11, c["textMuted"])
            ty = y + SZ["BUBBLE_PAD_Y"]
            for row in it["rows"]:
                cv.text(bx + SZ["BUBBLE_PAD_X"], ty + T["BODY"] / 2, row, T["BODY"], fill)
                ty += T["BODY"] + tokens["LINE_SPACING"]

    # ---------------------------------------------------------------- composer
    cv.rect(content_x, canvas_bottom, content_w, composer_h, c["composerBg"])
    cv.hline(content_x, canvas_bottom, content_w, c["borderSubtle"])
    pad_c = S["MD"]
    ebtn = SZ["ICON_BTN"]
    ey = canvas_bottom + composer_h - pad_c - 3 - ebtn
    cv.icon("smiley", content_x + pad_c + (ebtn - 16) / 2, ey + (ebtn - 16) / 2, 16,
            c["textSecondary"])
    send = SZ["SEND_BTN"]
    sx = content_x + content_w - pad_c - send
    sy = canvas_bottom + composer_h - pad_c - 2 - send
    # The send button is inactive until the field has content.
    cv.circle(sx + send / 2, sy + send / 2, send / 2, fill=c["hover"])
    cv.icon("arrow_up", sx + (send - 18) / 2, sy + (send - 18) / 2, 18, c["textDisabled"])
    fx = content_x + pad_c + ebtn + S["SM"]
    fw = sx - S["SM"] - fx
    fh = SZ["COMPOSER_FIELD_H"]
    fy = canvas_bottom + composer_h - pad_c - fh
    cv.rrect(fx, fy, fw, fh, radius(R["MD"]), fill=c["inputBg"], outline=c["borderSubtle"], width=1)
    cv.text(fx + S["MD"], fy + fh / 2, "Message Thrall…", T["BODY"], c["textMuted"])

    out = path or os.path.join("/tmp", "wtw_%s.png" % skin_id)
    flat = Image.new("RGB", cv.img.size, (16, 18, 22))
    flat.paste(cv.img, (0, 0), cv.img)
    flat.save(out)
    return out


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "midnight"
    layout = sys.argv[2] if len(sys.argv) > 2 else "hybrid"
    print(render(which, layout))


def render_settings(skin_id="midnight", path=None):
    """Renders the settings window from the same tokens the addon uses."""
    skin = tokens["skins"][skin_id]
    c = {k: rgba(v) for k, v in skin["colors"].items()}
    m = skin["metrics"]
    radius = lambda base: base * m.get("radiusScale", 1)

    W, H = SZ["SETTINGS_W"], SZ["SETTINGS_H"]
    cv = Canvas(W, H, c["bg0"])
    cv.rrect(0, 0, W, H, radius(R["LG"]), fill=c["bg0"], outline=c["borderSubtle"], width=1)

    head_h = SZ["TITLEBAR_H"] + 6
    cv.text(S["LG"], head_h / 2, "Settings", T["TITLE"], c["textPrimary"])
    cv.icon("close", W - S["SM"] - 26 + (26 - 13) / 2, (head_h - 13) / 2, 13, c["textSecondary"])
    cv.hline(0, head_h, W, c["borderSubtle"])

    # navigation
    nav_w = SZ["SETTINGS_NAV_W"]
    cv.rect(0, head_h, nav_w, H - head_h, c["bg1"])
    cv.vline(nav_w, head_h, H - head_h, c["borderSubtle"])
    fh = 28
    cv.rrect(S["MD"], head_h + S["MD"], nav_w - S["MD"] * 2, fh, radius(R["MD"]),
             fill=c["inputBg"], outline=c["borderSubtle"], width=1)
    cv.icon("search", S["MD"] * 2, head_h + S["MD"] + (fh - 14) / 2, 14, c["textMuted"])
    cv.text(S["MD"] + S["HUGE"], head_h + S["MD"] + fh / 2, "Search settings", T["SMALL"],
            c["textMuted"])

    categories = [("General", "sliders"), ("Appearance", "eye"), ("Messages", "message"),
                  ("Layout", "grid"), ("History", "clock"), ("Sounds", "volume"),
                  ("Notifications", "bell"), ("Animations", "refresh"), ("Combat", "shield"),
                  ("Links", "globe"), ("Advanced", "keyboard")]
    row_h = SZ["SETTINGS_ROW_H"]
    y = head_h + S["MD"] + fh + S["MD"]
    for i, (label, icon) in enumerate(categories):
        active = label == "Appearance"
        if active:
            cv.rrect(S["SM"], y, nav_w - S["SM"] * 2, row_h, radius(R["MD"]), fill=c["selected"])
            bar_w = SZ["ACCENT_BAR_W"]
            cv.rrect(S["SM"] + SZ["ACCENT_BAR_INSET"], y + S["SM"], bar_w,
                     row_h - S["SM"] * 2, bar_w / 2, fill=c["accent"])
        cv.icon(icon, S["LG"], y + (row_h - 14) / 2, 14,
                c["accent"] if active else c["textMuted"])
        cv.text(S["LG"] + 14 + S["MD"], y + row_h / 2, label, T["SMALL"],
                c["textPrimary"] if active else c["textSecondary"])
        y += row_h + 2

    # content
    view_w = W - nav_w
    available = min(SZ["SETTINGS_MAX_CONTENT"], view_w - S["XXL"] * 2)
    left = nav_w + max(S["XL"], (view_w - available) / 2)
    control_w = 190
    card_pad = S["LG"]

    cards = [
        ("Skin", [
            ("Skin", None, "dropdown", "Midnight"),
            ("Background opacity", None, "slider", "97%"),
            ("Corner radius", None, "dropdown", "Normal"),
            ("Drop shadows", None, "toggle", True),
        ]),
        ("Font", [
            ("Font", None, "dropdown", "Automatic"),
            ("Font size", None, "slider", "+0"),
        ]),
        ("Conversations", [
            ("Density", None, "dropdown", "Comfortable"),
            ("Use class colours", None, "toggle", True),
            ("Show avatars", None, "toggle", True),
            ("Avatar style", "Portrait when in range, class icon otherwise.",
             "dropdown", "Automatic"),
        ]),
    ]

    y = head_h + S["XL"]
    for title, rows in cards:
        heights = []
        for label, caption, kind, value in rows:
            h = 34
            if caption:
                h = max(h, 20 + T["MICRO"] + 8)
            heights.append(h)
        card_h = card_pad * 2 + sum(heights) + S["SM"] * (len(rows) - 1)
        cv.text(left + 2, y + 11, title, T["SMALL"], c["textMuted"])
        y += 22
        cv.rrect(left, y, available, card_h, radius(R["LG"]), fill=c["bg3"],
                 outline=c["borderSubtle"], width=1)

        ry = y + card_pad
        for i, (label, caption, kind, value) in enumerate(rows):
            h = heights[i]
            cv.text(left + card_pad, ry + 8, label, T["SMALL"], c["textPrimary"])
            if caption:
                cv.text(left + card_pad, ry + 8 + T["SMALL"] + 4, caption, T["MICRO"],
                        c["textMuted"])
            cx = left + available - card_pad - control_w
            cy = ry + h / 2
            if kind == "toggle":
                tw, th, knob = SZ["TOGGLE_W"], SZ["TOGGLE_H"], SZ["TOGGLE_KNOB"]
                tx = left + available - card_pad - tw
                cv.rrect(tx, cy - th / 2, tw, th, th / 2,
                         fill=c["accent"] if value else c["hover"])
                kx = tx + (tw - knob - 2 if value else 2)
                cv.circle(kx + knob / 2, cy, knob / 2,
                          fill=c["onAccent"] if value else c["textSecondary"])
            elif kind == "dropdown":
                cv.rrect(cx, cy - 15, control_w, 30, radius(R["MD"]), fill=c["inputBg"],
                         outline=c["borderSubtle"], width=1)
                cv.text(cx + S["MD"], cy, value, T["SMALL"], c["textPrimary"])
                cv.icon("chevron_down", cx + control_w - S["SM"] - 14, cy - 7, 14, c["textMuted"])
            else:
                track = control_w - 46
                cv.rrect(cx + SZ["SLIDER_THUMB"] / 2, cy - 2, track - SZ["SLIDER_THUMB"], 4, 2,
                         fill=c["hover"])
                cv.rrect(cx + SZ["SLIDER_THUMB"] / 2, cy - 2,
                         (track - SZ["SLIDER_THUMB"]) * 0.75, 4, 2, fill=c["accent"])
                cv.circle(cx + SZ["SLIDER_THUMB"] / 2 + (track - SZ["SLIDER_THUMB"]) * 0.75, cy,
                          SZ["SLIDER_THUMB"] / 2, fill=c["textPrimary"])
                cv.text(cx + control_w, cy, value, T["SMALL"], c["textSecondary"], anchor="rm")
            ry += h + S["SM"]
        y += card_h + S["XL"]

    out = path or "/tmp/wtw_settings_%s.png" % skin_id
    flat = Image.new("RGB", cv.img.size, (16, 18, 22))
    flat.paste(cv.img, (0, 0), cv.img)
    flat.save(out)
    return out
