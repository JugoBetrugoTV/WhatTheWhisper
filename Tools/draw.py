"""Tiny vector helpers on a supersampled canvas.

All icon geometry is authored in a 64x64 unit space; the canvas is rendered at
`S` times that and downsampled with Lanczos, which gives clean antialiasing
without needing a real rasteriser.
"""
import math

WHITE = (255, 255, 255, 255)


class Pen:
    def __init__(self, draw, scale):
        self.d = draw
        self.s = scale

    def _p(self, v):
        return v * self.s

    def line(self, x1, y1, x2, y2, w, fill=WHITE, cap=True):
        s = self.s
        self.d.line([(x1 * s, y1 * s), (x2 * s, y2 * s)], fill=fill, width=int(round(w * s)))
        if cap:
            r = w * s / 2.0
            for (cx, cy) in ((x1 * s, y1 * s), (x2 * s, y2 * s)):
                self.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

    def polyline(self, pts, w, fill=WHITE):
        for i in range(len(pts) - 1):
            self.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w, fill)

    def circle(self, cx, cy, r, fill=None, outline=None, w=0):
        s = self.s
        box = [(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s]
        self.d.ellipse(box, fill=fill, outline=outline, width=int(round(w * s)))

    def rrect(self, x1, y1, x2, y2, r, fill=None, outline=None, w=0):
        s = self.s
        self.d.rounded_rectangle(
            [x1 * s, y1 * s, x2 * s, y2 * s],
            radius=r * s,
            fill=fill,
            outline=outline,
            width=int(round(w * s)),
        )

    def ellipse(self, cx, cy, rx, ry, fill=None, outline=None, w=0):
        s = self.s
        box = [(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s]
        self.d.ellipse(box, fill=fill, outline=outline, width=int(round(w * s)))

    def rect(self, x1, y1, x2, y2, fill=WHITE):
        s = self.s
        self.d.rectangle([x1 * s, y1 * s, x2 * s, y2 * s], fill=fill)

    def poly(self, pts, fill=WHITE, outline=None, w=0):
        s = self.s
        p = [(x * s, y * s) for (x, y) in pts]
        self.d.polygon(p, fill=fill, outline=outline, width=int(round(w * s)) if w else 0)

    def arc(self, cx, cy, r, a0, a1, w, fill=WHITE, steps=64):
        pts = []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        self.polyline(pts, w, fill)

    def wedge(self, cx, cy, r, a0, a1, fill=WHITE, steps=48):
        pts = [(cx, cy)]
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        self.poly(pts, fill)
