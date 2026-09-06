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
from tga import write_tga  # noqa: E402

OUT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "WhatTheWhisper", "Art"))
os.makedirs(OUT, exist_ok=True)

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
white_alpha(a).save(os.path.join(OUT, "_preview_round.png"))

# --------------------------------------------------------------- Shadow ----
a = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(a)
d.rounded_rectangle([26, 26, N - 27, N - 27], radius=18, fill=255)
a = a.filter(ImageFilter.GaussianBlur(11))
write_tga(os.path.join(OUT, "Shadow.tga"), white_alpha(a))
white_alpha(a).save(os.path.join(OUT, "_preview_shadow.png"))

print("shapes written to", OUT)
