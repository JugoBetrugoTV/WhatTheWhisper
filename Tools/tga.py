"""Minimal 32-bit uncompressed TGA writer for WoW addon art.

WoW loads uncompressed 32-bit BGRA TGA files. We always emit a top-down image
(descriptor bit 5 set) with 8 alpha bits, which is the layout Blizzard's own
loader and every shipping addon uses.
"""
import struct


def write_tga(path, img):
    """img: PIL RGBA Image."""
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,       # id length
        0,       # colour map type
        2,       # uncompressed true-colour
        0, 0, 0, # colour map spec
        0, 0,    # x/y origin
        w, h,
        32,      # bits per pixel
        0x28,    # 8 alpha bits + top-down origin
    )
    px = img.tobytes()  # RGBA
    out = bytearray(len(px))
    out[0::4] = px[2::4]  # B
    out[1::4] = px[1::4]  # G
    out[2::4] = px[0::4]  # R
    out[3::4] = px[3::4]  # A
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(bytes(out))


def bleed(img, passes=6):
    """Push colour outwards into transparent pixels.

    Bilinear filtering samples RGB even where alpha is 0, so transparent black
    would produce dark fringes around every antialiased edge. Dilating the
    colour into the transparent region removes that entirely.
    """
    from PIL import Image
    w, h = img.size
    px = list(img.getdata())
    for _ in range(passes):
        changed = False
        new = list(px)
        for y in range(h):
            base = y * w
            for x in range(w):
                i = base + x
                if px[i][3] != 0:
                    continue
                r = g = b = n = 0
                for dy in (-1, 0, 1):
                    yy = y + dy
                    if yy < 0 or yy >= h:
                        continue
                    for dx in (-1, 0, 1):
                        xx = x + dx
                        if xx < 0 or xx >= w:
                            continue
                        p = px[yy * w + xx]
                        if p[3] != 0:
                            r += p[0]; g += p[1]; b += p[2]; n += 1
                if n:
                    new[i] = (r // n, g // n, b // n, 0)
                    changed = True
        px = new
        if not changed:
            break
    out = Image.new("RGBA", (w, h))
    out.putdata(px)
    return out
