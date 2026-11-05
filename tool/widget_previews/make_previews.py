#!/usr/bin/env python3
"""Draws the picture each Android widget shows in the home screen's widget picker (item 83).

Every widget's appwidget-provider XML points android:previewImage at one of these, so the
picker shows what the widget looks like with made-up tasks instead of a blank box or the app icon.

Run from the repo root:  python3 tool/widget_previews/make_previews.py   (needs: pip install pillow)
Writes android/app/src/main/res/drawable-nodpi/widget_preview_*.png.
"""

import calendar
import colorsys
import datetime
import os

from PIL import Image, ImageDraw, ImageFont

S = 3  # pixels per dp
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "res", "drawable-nodpi")

INK = (0, 0, 0, 221)
FAINT = (0, 0, 0, 153)
BG = (255, 255, 255, 242)
TILE = (240, 242, 245, 255)
BLUE = (91, 141, 239, 255)
GREEN = (67, 160, 71, 255)
ORANGE = (230, 81, 0, 255)
NAVY = (26, 95, 180, 255)
TEAL = (0, 137, 123, 255)
EVENT = (227, 238, 246, 255)
GREY = (213, 213, 213, 255)

FONT_DIRS = ["/usr/share/fonts/opentype/inter", "/usr/share/fonts/truetype/dejavu", "/Library/Fonts", "C:/Windows/Fonts"]
FONT_NAMES = {"bold": ["Inter-Bold.otf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf", "arialbd.ttf"],
              "regular": ["Inter-Regular.otf", "DejaVuSans.ttf", "Arial.ttf", "arial.ttf"]}
_fonts = {}


def font(size, bold=False):
    key = (size, bold)
    if key not in _fonts:
        f = None
        for d in FONT_DIRS:
            for n in FONT_NAMES["bold" if bold else "regular"]:
                p = os.path.join(d, n)
                if os.path.exists(p):
                    f = ImageFont.truetype(p, int(size * S))
                    break
            if f:
                break
        _fonts[key] = f or ImageFont.load_default()
    return _fonts[key]


def age(p):
    """The app's green-to-red block colour, p from 0 (new) to 1 (red)."""
    r, g, b = colorsys.hsv_to_rgb(120 * (1 - p) / 360, 0.6, 0.88)
    return (int(r * 255), int(g * 255), int(b * 255), 255)


class W:
    """One widget picture, drawn in dp."""

    def __init__(self, cols, rows):
        self.w, self.h = cols * 72 - 8, rows * 70 - 8
        self.img = Image.new("RGBA", (self.w * S, self.h * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.rect(0, 0, self.w, self.h, BG, 16)

    def rect(self, x, y, w, h, fill, r=0, outline=None, width=1):
        box = [x * S, y * S, (x + w) * S - 1, (y + h) * S - 1]
        if r:
            self.d.rounded_rectangle(box, r * S, fill=fill, outline=outline, width=int(width * S))
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=int(width * S))

    def text(self, x, y, s, size=13, bold=False, fill=INK, anchor="la", maxw=None):
        f = font(size, bold)
        if maxw is not None:
            while s and self.d.textlength(s, font=f) > maxw * S:
                s = s[:-2] + "…" if len(s) > 2 else ""
        self.d.text((x * S, y * S), s, font=f, fill=fill, anchor=anchor)

    def textw(self, s, size=13, bold=False):
        return self.d.textlength(s, font=font(size, bold)) / S

    def circle(self, cx, cy, r, fill=None, outline=None, width=1.5):
        self.d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=fill, outline=outline,
                       width=int(width * S))

    def line(self, pts, fill, width=1.5, dash=None):
        pts = [(x * S, y * S) for x, y in pts]
        if not dash:
            self.d.line(pts, fill=fill, width=int(width * S), joint="curve")
            return
        on, off = dash[0] * S, dash[1] * S
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            length = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
            t = 0.0
            while t < length:
                t1 = min(t + on, length)
                self.d.line([(x0 + (x1 - x0) * t / length, y0 + (y1 - y0) * t / length),
                             (x0 + (x1 - x0) * t1 / length, y0 + (y1 - y0) * t1 / length)],
                            fill=fill, width=int(width * S))
                t = t1 + off

    def box(self, x, y, size=14, ticked=False, colour=INK):
        self.rect(x, y, size, size, None, 3, outline=colour, width=1.6)
        if ticked:
            self.line([(x + 3, y + size / 2), (x + size / 2.4, y + size - 4), (x + size - 3, y + 3)], colour, 1.8)

    def plus(self, cx, cy, r=6, colour=INK):
        self.line([(cx - r, cy), (cx + r, cy)], colour, 2)
        self.line([(cx, cy - r), (cx, cy + r)], colour, 2)

    def snooze(self, cx, cy, colour=INK):
        self.circle(cx, cy, 6, outline=colour, width=1.4)
        self.line([(cx, cy - 3.5), (cx, cy), (cx + 2.5, cy + 2)], colour, 1.4)

    def arrow(self, cx, cy, colour=INK, left=False):
        k = -1 if left else 1
        self.line([(cx - 3 * k, cy - 5), (cx + 2 * k, cy), (cx - 3 * k, cy + 5)], colour, 2)

    def header(self, title, plus=True, y=6):
        self.text(14, y + 14, title, 16, True, anchor="lm", maxw=self.w - 50)
        if plus:
            self.plus(self.w - 22, y + 14, 7)

    def task_row(self, x, y, w, title, due, p, h=30, snooze=True, event=False, overdue=False, locked=False):
        self.rect(x, y, w, h, EVENT if event else GREY if locked else age(p), 6)
        if event:
            self.rect(x + 9, y + h / 2 - 6, 13, 12, None, 2, outline=INK, width=1.4)
            self.line([(x + 9, y + h / 2 - 2), (x + 22, y + h / 2 - 2)], INK, 1.4)
        else:
            self.box(x + 9, y + h / 2 - 7)
        right = x + w - (30 if snooze else 8)
        dw = self.textw(due, 11) if due else 0
        self.text(x + 32, y + h / 2, title, 13, True, anchor="lm", maxw=right - x - 38 - dw)
        if due:
            self.text(right, y + h / 2, due, 11, fill=(139, 0, 0, 255) if overdue else INK, anchor="rm")
        if snooze and not event:
            self.snooze(x + w - 15, y + h / 2)

    def save(self, name):
        os.makedirs(OUT, exist_ok=True)
        img = self.img.quantize(colors=255, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
        img.save(os.path.join(OUT, f"widget_preview_{name}.png"), optimize=True)


TASKS = [("Call the plumber", "Overdue", 1.0, True), ("Pay the gas bill", "16:00", 0.75, False),
         ("Book the car service", "Tomorrow", 0.5, False), ("Plan the garden", "Fri 13 Nov", 0.3, False),
         ("Read chapter 4", "", 0.1, False), ("Sort the photos", "", 0.0, False)]


def task_list(name, title, rows):
    w = W(4, 3)
    w.header(title)
    y = 40
    for t, due, p, od, *ev in rows:
        if y + 30 > w.h - 4:
            break
        w.task_row(6, y, w.w - 12, t, due, p, event=bool(ev), overdue=od)
        y += 34
    w.save(name)


def compact():
    w = W(2, 2)
    w.text(12, 18, "All tasks", 14, True, anchor="lm")
    w.text(12, 40, "12 open · 2 overdue", 12, fill=FAINT, anchor="lm")
    for i, (d, t) in enumerate([("16:00", "Pay the gas bill"), ("Tomorrow", "Car service"), ("Fri", "Plan the garden")]):
        w.text(12, 66 + i * 20, f"{d}  {t}", 12, anchor="lm", maxw=w.w - 20)
    w.save("compact")


def quick_add():
    w = W(2, 1)
    w.rect(8, 10, w.w - 60, w.h - 20, TILE, 20)
    w.plus(26, w.h / 2, 6)
    w.text(40, w.h / 2, "Add", 13, True, anchor="lm")
    w.circle(w.w - 28, w.h / 2, 18, fill=TEAL)
    cx, cy = w.w - 28, w.h / 2
    w.rect(cx - 4, cy - 10, 8, 13, (255, 255, 255, 255), 4)
    w.line([(cx - 7, cy - 1), (cx - 7, cy + 1), (cx, cy + 7), (cx + 7, cy + 1), (cx + 7, cy - 1)], (255, 255, 255, 255), 1.6)
    w.line([(cx, cy + 7), (cx, cy + 10)], (255, 255, 255, 255), 1.6)
    w.save("quick_add")


def focus():
    w = W(4, 1)
    w.rect(6, 6, w.w - 12, w.h - 12, age(0.7), 12)
    w.box(18, w.h / 2 - 9, 18)
    w.text(46, w.h / 2 - 8, "★ Finish the tax return", 15, True, anchor="lm", maxw=w.w - 70)
    w.text(46, w.h / 2 + 11, "Due tomorrow · 3 of 5 steps", 11, anchor="lm")
    w.save("focus")


def checklist():
    w = W(2, 3)
    w.text(12, 20, "Pack for trip 2/5", 14, True, anchor="lm", maxw=w.w - 20)
    for i, (t, done) in enumerate([("Passport", True), ("Chargers", True), ("Swimsuit", False), ("Sun cream", False),
                                   ("Book", False)]):
        y = 42 + i * 28
        w.box(12, y, 15, ticked=done)
        w.text(34, y + 7.5, t, 13, fill=FAINT if done else INK, anchor="lm")
    w.save("checklist")


def stats():
    w = W(2, 1)
    for i, (n, label) in enumerate([("5", "done this week"), ("3", "day streak")]):
        cx = w.w / 4 + i * w.w / 2
        w.text(cx, 24, n, 22, True, anchor="mm")
        w.text(cx, 46, label, 9, fill=FAINT, anchor="mm")
    w.save("stats")


DUE = {3: 1, 6: 2, 9: 1, 12: 1, 13: 3, 17: 1, 20: 1, 24: 2, 27: 1}
TODAY = 12


def month_grid(w, x, y, cw, ch, size=10):
    for i, l in enumerate("MTWTFSS"):
        w.text(x + cw * (i + 0.5), y + 6, l, size, fill=FAINT, anchor="mm")
    y += 14
    first = 6  # The 1st falls on a Sunday in the sample month (November 2026).
    days = 30
    cells = [(31 - first + 1 + i, False) for i in range(first)] + [(d, True) for d in range(1, days + 1)]
    while len(cells) < 42:
        cells.append((len(cells) - first - days + 1, False))
    for i, (d, inm) in enumerate(cells):
        cx, cy = x + cw * (i % 7 + 0.5), y + ch * (i // 7) + ch * 0.4
        if inm and d == TODAY:
            w.circle(cx, cy, size * 0.95, outline=NAVY, width=1.5)
        w.text(cx, cy, str(d), size, fill=INK if inm else (0, 0, 0, 85), anchor="mm")
        if inm and d in DUE:
            w.circle(cx, cy + size * 1.15, 2.2, fill=(46, 125, 50, 255))


def month():
    w = W(3, 3)
    w.text(w.w / 2, 14, "November", 13, True, anchor="mm")
    month_grid(w, 6, 24, (w.w - 12) / 7, 25)
    w.save("month")


def calendar_widget():
    w = W(4, 3)
    w.header("November 2026", y=4)
    half = (w.w - 18) / 2
    month_grid(w, 6, 34, half / 7, 24, 9)
    x = 12 + half
    rows = [("Plumber", "11 Nov", 1.0, True), ("Gas bill", "16:00", 0.75, False), ("Dentist", "10:30", 0, False, True),
            ("Car service", "Fri", 0.5, False), ("Garden", "Sat", 0.3, False), ("Mum's card", "Tue", 0.2, False)]
    y = 36
    for t, due, p, od, *ev in rows:
        if y + 26 > w.h - 4:
            break
        w.task_row(x, y, half, t, due, p, h=26, snooze=False, event=bool(ev), overdue=od)
        y += 29
    w.save("calendar")


STAGES = [("Backlog", 6), ("Up next", 3), ("In progress", 2), ("Blocked", 1), ("Done", 9)]


def board_summary():
    w = W(4, 1)
    n = len(STAGES)
    tw = (w.w - 12 - 4 * (n - 1)) / n
    for i, (s, c) in enumerate(STAGES):
        x = 6 + i * (tw + 4)
        w.rect(x, 8, tw, w.h - 16, TILE, 10)
        w.text(x + tw / 2, w.h / 2 - 8, str(c), 17, True, anchor="mm")
        w.text(x + tw / 2, w.h / 2 + 11, ("• " if i == 2 else "") + s, 9, fill=FAINT, anchor="mm", maxw=tw - 4)
    w.save("board_summary")


def stage_list():
    w = W(4, 3)
    w.header("Kanban board", plus=False)
    w.arrow(20, 50, left=True)
    w.text(w.w / 2, 50, "In progress · 3", 13, True, anchor="mm")
    w.arrow(w.w - 20, 50)
    for i, (t, meta, p) in enumerate([("Paint the fence", "3 days · 2/4 steps", 0.6), ("Write the report", "5 h", 0.3),
                                      ("Fix the bike", "1 day", 0.15)]):
        y = 66 + i * 40
        w.rect(6, y, w.w - 12, 36, age(p), 8)
        w.text(16, y + 12, t, 13, True, anchor="lm")
        w.text(16, y + 26, meta, 10, anchor="lm")
        w.arrow(w.w - 22, y + 18)
    w.save("stage_list")


def now_doing():
    w = W(4, 3)
    w.text(14, 16, "Now doing", 11, True, fill=FAINT, anchor="lm")
    w.text(w.w - 14, 16, "In progress 2 days", 10, fill=FAINT, anchor="rm")
    w.text(14, 38, "Paint the fence", 18, True, anchor="lm")
    w.text(14, 58, "Home · due Sat", 11, fill=FAINT, anchor="lm")
    for i, (t, done) in enumerate([("Buy paint", True), ("Sand the boards", True), ("First coat", False)]):
        y = 72 + i * 22
        w.box(14, y, 14, ticked=done)
        w.text(36, y + 7, t, 12, fill=FAINT if done else INK, anchor="lm")
    by = w.h - 38
    bw = (w.w - 34) / 2
    w.rect(12, by, bw, 28, TILE, 14)
    w.text(12 + bw / 2, by + 14, "Next: Blocked", 12, True, anchor="mm")
    w.rect(22 + bw, by, bw, 28, GREEN, 14)
    w.text(22 + bw * 1.5, by + 14, "Done", 12, True, fill=(255, 255, 255, 255), anchor="mm")
    w.save("now")


def board_steps():
    w = W(4, 3)
    w.header("Steps on the board · 5 open", plus=False)
    y = 38
    for stage, steps in [("Up next", [("Get quotes", "Kitchen · step 2")]),
                         ("In progress", [("Draft the plan", "Kitchen · step 1"), ("Measure up", "Bathroom · step 1")])]:
        w.text(14, y + 8, stage, 11, True, fill=FAINT, anchor="lm")
        y += 18
        for t, meta in steps:
            w.rect(6, y, w.w - 12, 34, TILE, 8)
            w.box(14, y + 10, 14)
            w.text(38, y + 11, t, 13, True, anchor="lm")
            w.text(38, y + 25, meta, 10, fill=FAINT, anchor="lm")
            w.arrow(w.w - 22, y + 17)
            y += 38
    w.save("board_steps")


def matrix():
    w = W(4, 3)
    w.text(14, 16, "Matrix", 14, True, anchor="lm")
    w.text(w.w - 14, 16, "11 tasks", 11, fill=FAINT, anchor="rm")
    boxes = [("Do · 3", [("Call the plumber", 1.0), ("Pay the gas bill", 0.75)]),
             ("Decide · 4", [("Plan the garden", 0.3), ("New phone?", 0.2)]),
             ("Delegate · 2", [("Car service", 0.5)]), ("Delete · 2", [("Old emails", 0.1)])]
    bw, bh = (w.w - 16) / 2, (w.h - 38) / 2
    for i, (name, rows) in enumerate(boxes):
        x, y = 6 + (i % 2) * (bw + 4), 30 + (i // 2) * (bh + 4)
        w.rect(x, y, bw, bh, TILE, 8)
        w.text(x + 8, y + 12, name, 11, True, anchor="lm")
        for j, (t, p) in enumerate(rows):
            ry = y + 28 + j * 18
            w.rect(x + 8, ry - 6, 4, 12, age(p), 1)
            w.text(x + 17, ry, t, 11, anchor="lm", maxw=bw - 24)
    w.save("matrix")


def worked():
    w = W(4, 3)
    w.header("Work · Worked today · 2 of 4", plus=False)
    rows = [("Quarterly report", True, "11011", "4 this week"), ("Client emails", True, "10101", "3 this week"),
            ("Update the website", False, "01000", "1 this week"), ("Tidy the drive", False, "00000", "")]
    for i, (t, on, days, extra) in enumerate(rows):
        y = 40 + i * 38
        w.circle(22, y + 16, 8, fill=GREEN if on else None, outline=GREEN if on else INK)
        if on:
            w.line([(18, y + 16), (21, y + 19.5), (26, y + 12.5)], (255, 255, 255, 255), 1.8)
        w.text(40, y + 10, t, 13, True, anchor="lm")
        for k in range(7):
            cx = 43 + k * 9
            if k < len(days) and days[k] == "1":
                w.circle(cx, y + 26, 3, fill=INK)
            elif k < len(days):
                w.circle(cx, y + 26, 3, outline=INK, width=1)
            else:
                w.circle(cx, y + 26, 1, fill=FAINT)
        if extra:
            w.text(43 + 7 * 9 + 4, y + 26, extra, 10, fill=FAINT, anchor="lm")
    w.save("worked")


def chart_frame(title, note):
    w = W(4, 3)
    w.text(12, 16, title, 14, True, anchor="lm")
    w.text(12, w.h - 16, note, 11, fill=FAINT, anchor="lm", maxw=w.w - 20)
    return w, 8, 30, w.w - 16, w.h - 62


def added_done():
    added = [2, 1, 3, 0, 2, 1, 4, 1, 0, 2, 3, 1, 2, 0, 1, 3, 2, 1, 0, 2, 1, 3, 1, 2, 0, 1, 2, 3]
    done = [1, 2, 1, 1, 2, 0, 2, 3, 1, 1, 2, 2, 1, 1, 2, 1, 3, 1, 1, 1, 2, 2, 2, 1, 1, 2, 1, 2]
    open_, n = [], 12
    for a, d in zip(added, done):
        n += a - d
        open_.append(n)
    w, x, y, cw, ch = chart_frame("Stats chart: added vs done", f"Last 4 weeks: {sum(added)} added (blue), "
                                  f"{sum(done)} done (green), {open_[-1]} open now (line)")
    top, otop = max(added + done), max(open_)
    slot = cw / len(added)
    bar = slot * 0.4
    base = y + ch
    w.line([(x, base), (x + cw, base)], FAINT, 1)
    for i, (a, d) in enumerate(zip(added, done)):
        bx = x + i * slot + slot * 0.1
        if a:
            w.rect(bx, base - ch * a / top, bar, ch * a / top, BLUE)
        if d:
            w.rect(bx + bar, base - ch * d / top, bar, ch * d / top, GREEN)
    w.line([(x + i * slot + slot / 2, base - ch * 0.9 * v / otop) for i, v in enumerate(open_)], ORANGE, 2)
    w.save("added_done")


def burn_down():
    w, x, y, cw, ch = chart_frame("Burn-down", "8 left of 20 · at this pace done Thu 26 Nov, 2 days late")
    span, end, total = 24, 22, 20
    left = [20, 20, 19, 18, 18, 17, 15, 15, 14, 13, 12, 12, 10, 9, 8]

    def px(i):
        return x + cw * i / span

    def py(v):
        return y + ch * (1 - v / total)

    w.line([(x, y + ch), (x + cw, y + ch)], FAINT, 1)
    t = len(left) - 1
    w.line([(px(t), y), (px(t), y + ch)], (26, 95, 180, 102), 1)
    w.line([(px(0), py(total)), (px(end), py(0))], FAINT, 1.5, dash=(6, 4))
    w.line([(px(i), py(v)) for i, v in enumerate(left)], NAVY, 2.5)
    w.line([(px(t), py(left[-1])), (px(span), py(0))], (198, 40, 40, 255), 2, dash=(2, 4))
    w.save("burn_down")


if __name__ == "__main__":
    task_list("task_list", "All tasks", TASKS)
    task_list("today", "Today", [TASKS[0], ("Team meeting", "09:30", 0, False, True), TASKS[1],
                                 ("Dentist", "14:00", 0, False, True), ("Water the plants", "18:00", 0.4, False)])
    compact()
    quick_add()
    focus()
    checklist()
    stats()
    month()
    calendar_widget()
    board_summary()
    stage_list()
    now_doing()
    board_steps()
    matrix()
    worked()
    added_done()
    burn_down()
    print("Wrote previews to", os.path.normpath(OUT))
