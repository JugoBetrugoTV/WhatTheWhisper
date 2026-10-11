"""Generates the geometry textures the UI toolkit is built from.

Round.tga   128x128 antialiased white disc. Used three ways:
              * quadrant tex-coords -> the four corners of every rounded rect
              * whole texture as a MaskTexture -> circular avatars
              * whole texture tinted -> dots, pills, badges
Shadow.tga  128x128 blurred rounded rect, 9-sliced into a soft drop shadow.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402
from tga import write_tga, bleed  # noqa: E402

OUT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "WhatTheWhisper", "Art"))
os.makedirs(OUT, exist_ok=True)


def preview(name):
    """Design previews live outside the addon folder; only .tga ships."""
    directory = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview")
    os.makedirs(directory, exist_ok=True)
    return os.path.join(directory, name)


SS = 8


def white_alpha(alpha_img):
    size = alpha_img.size
    w = Image.new("L", size, 255)
    return Image.merge("RGBA", (w, w, w, alpha_img))


# ---------------------------------------------------------------- Round ----
N = 128
a = Image.new("L", (N * SS, N * SS), 0)
d = ImageDraw.Draw(a)
d.ellipse([0, 0, N * SS - 1, N * SS - 1], fill=255)
a = a.resize((N, N), Image.LANCZOS)
write_tga(os.path.join(OUT, "Round.tga"), white_alpha(a))
white_alpha(a).save(preview("round.png"))

# --------------------------------------------------------------- Shadow ----
a = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(a)
d.rounded_rectangle([26, 26, N - 27, N - 27], radius=18, fill=255)
a = a.filter(ImageFilter.GaussianBlur(11))
write_tga(os.path.join(OUT, "Shadow.tga"), white_alpha(a))
white_alpha(a).save(preview("shadow.png"))

print("shapes written to", OUT)

# ----------------------------------------------------------------- Logo ----
# Addon list icon: an accent tile with a speech bubble knocked out of it.
N2 = 64
img = Image.new("RGBA", (N2 * SS, N2 * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
s = SS
d.rounded_rectangle([2 * s, 2 * s, 62 * s, 62 * s], radius=14 * s, fill=(90, 124, 250, 255))
d.rounded_rectangle([13 * s, 15 * s, 51 * s, 42 * s], radius=9 * s, fill=(255, 255, 255, 255))
d.polygon([(22 * s, 40 * s), (22 * s, 53 * s), (35 * s, 41 * s)], fill=(255, 255, 255, 255))
for cx in (23, 32, 41):
    d.ellipse([(cx - 3) * s, (28 - 3) * s, (cx + 3) * s, (28 + 3) * s], fill=(90, 124, 250, 255))
img = img.resize((N2, N2), Image.LANCZOS)
# The logo is the only coloured art with an alpha edge, so it is the only one
# that showed a dark halo: without dilating the colour outwards, the client's
# filtering samples transparent black around every rounded corner.
img = bleed(img)
write_tga(os.path.join(OUT, "Logo.tga"), img)
img.save(preview("logo.png"))
print("logo written")
