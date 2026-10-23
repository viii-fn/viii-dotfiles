#!/usr/bin/env python3
"""
pixel-scenes - a different minimalist pixel-art loop.gif for every theme, drawn in that theme's
own palette.json colors. One command, all themes.

  pixel-scenes                        # every theme in ~/viii-shell-2/themes
  pixel-scenes --preview sheet.png    # contact sheet only, writes no gifs
  pixel-scenes --only sunset,wood     # just some themes
  pixel-scenes --scene campfire --only kyrie   # force a scene on a theme
  pixel-scenes --list                 # show the scenes
  pixel-scenes --name scene.gif       # write scene.gif instead of loop.gif (leaves loop.gif alone)

An existing loop.gif is kept as loop.old.gif (or loop.old-<time>.gif if that exists too).
Install:  install -Dm755 pixel_scenes.py ~/.local/bin/pixel-scenes      (needs python-pillow)
"""
import argparse, json, math, random, shutil, subprocess, sys, time
from pathlib import Path
from PIL import Image, ImageDraw

W, H, S, N = 171, 96, 8, 48          # 171*8 x 96*8 = 1368x768, 48 frames
TAU = 2 * math.pi
SK0, SK1, SK2, SK3, DARK, ACC, ACH, LIT, DIM, ACD, ACM, BLK, PALE = range(13)

# ------------------------------------------------------------------ colors
def hex_rgb(h, d):
    if not isinstance(h, str): return d
    h = h.strip().lstrip("#")
    if len(h) in (3, 4): h = "".join(c * 2 for c in h[:3])
    try: return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) if len(h) >= 6 else d
    except ValueError: return d

def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
WHITE, BLACK = (255, 255, 255), (0, 0, 0)

def make_palette(path):
    try: p = json.loads(Path(path).read_text())
    except Exception: p = {}
    bg = hex_rgb(p.get("bg"), (16, 20, 28)); sf = hex_rgb(p.get("surface"), (28, 36, 58))
    fg = hex_rgb(p.get("fg"), (229, 229, 229)); ac = hex_rgb(p.get("accent"), (59, 130, 246))
    ah = hex_rgb(p.get("accentHi") or p.get("accent"), (96, 165, 250))
    cols = [lerp(bg, BLACK, .30), bg, sf, lerp(sf, ac, .30), lerp(bg, BLACK, .55), ac, ah,
            lerp(fg, WHITE, .30), lerp(bg, fg, .50), lerp(ac, bg, .60), lerp(ac, bg, .35),
            lerp(bg, BLACK, .78), lerp(ah, WHITE, .60)]
    flat = []
    for c in cols: flat += list(c)
    return flat + [0] * (768 - len(flat))

# ----------------------------------------------------------------- helpers
def sn(f, k=1, p=0): return math.sin(TAU * k * f / N + p)
def bands(d, cols, y0, y1):
    h = (y1 - y0) / len(cols)
    for i, c in enumerate(cols):
        d.rectangle([0, int(y0 + i * h), W, int(y0 + (i + 1) * h) + 1], fill=c)
def starfield(r, n, ymax): return [(r.randrange(W), r.randrange(ymax), r.randrange(24)) for _ in range(n)]
def twinkle(d, stars, f):
    for x, y, p in stars: d.point((x, y), fill=LIT if (f + p) % 24 < 3 else DIM)
def hills(d, base, amp, k, col, ph=0):
    for x in range(W): d.line([x, int(base + amp * math.sin(x / k + ph) + amp * .4 * math.sin(x / (k * .4))), x, H], fill=col)

# ------------------------------------------------------------------ scenes
def sc_atmos():
    r = random.Random(1); st = starfield(r, 34, 60)
    cl = [(r.randrange(W), r.randrange(12, 46), r.uniform(0, 6.28)) for _ in range(4)]
    def frame(f, d):
        bands(d, [SK0, SK1, SK2, SK3], 0, H); twinkle(d, st, f)
        d.ellipse([130, 10, 148, 28], fill=PALE); d.point((136, 16), fill=LIT); d.point((142, 21), fill=LIT)
        if 8 <= f < 17:
            k = f - 8; x, y = 30 + k * 9, 6 + k * 4; d.line([x - 8, y - 4, x, y], fill=LIT); d.point((x, y), fill=PALE)
        for x0, y, p in cl:
            x = x0 + 12 * sn(f, 1, p); d.ellipse([x, y, x + 26, y + 7], fill=ACM); d.ellipse([x + 6, y - 3, x + 19, y + 4], fill=ACM)
        hills(d, 80, 6, 18, DARK)
    return frame

def sc_desert():
    r = random.Random(2)
    def dune(x, base, amp, k, ph): return base + amp * math.sin(x / k + ph)
    def frame(f, d):
        bands(d, [SK1, SK2, SK3, ACM], 0, 66)
        rr = 9 + (1 if (f // 12) % 2 else 0); d.ellipse([125 - rr - 3, 34 - rr - 3, 125 + rr + 3, 34 + rr + 3], fill=ACM); d.ellipse([125 - rr, 34 - rr, 125 + rr, 34 + rr], fill=ACH)
        for base, amp, k, ph, col in ((62, 5, 22, .5, ACM), (72, 6, 17, 2.0, ACD), (84, 5, 25, 4.0, DARK)):
            for x in range(W): d.line([x, int(dune(x, base, amp, k, ph)), x, H], fill=col)
        cy = int(dune(48, 84, 5, 25, 4.0)); d.rectangle([47, cy - 15, 49, cy + 2], fill=BLK); d.rectangle([43, cy - 10, 49, cy - 8], fill=BLK); d.rectangle([43, cy - 14, 44, cy - 8], fill=BLK); d.rectangle([52, cy - 11, 55, cy - 9], fill=BLK); d.rectangle([54, cy - 15, 55, cy - 9], fill=BLK)
        x = (f * (W + 24) / N) % (W + 24) - 12; y = dune(x, 72, 6, 17, 2.0) - 4 - abs(math.sin(f * .6)) * 5
        d.ellipse([x - 3, y - 3, x + 3, y + 3], outline=LIT)
        for i in range(5):
            xx = 70 + i * 16; yy = 56 - (f * 1 + i * 9) % 12; d.point((xx + int(2 * sn(f, 2, i)), yy), fill=ACH)
    return frame

def sc_sunset():
    r = random.Random(3)
    def frame(f, d):
        bands(d, [SK0, SK1, SK2, SK3, ACM, ACC], 0, 60); bob = 2 * sn(f)
        d.ellipse([71, 40 + bob, 99, 68 + bob], fill=ACH)
        bands(d, [ACM, ACD, DARK, BLK], 60, H)
        for i, y in enumerate(range(62, 90, 3)):
            w = max(2, int(15 - i * 1.2 + 3 * sn(f, 2, i))); d.line([85 - w, y, 85 + w, y], fill=PALE if i % 2 == 0 else ACH)
        for y in (66, 74, 82, 90):
            for x in range(-10, W, 26):
                xx = x + 7 * sn(f, 1, y); d.line([xx, y, xx + 9, y], fill=ACC)
        for x0, y0, sp in ((10, 18, 1), (90, 28, 1)):
            x = (x0 + f * (W + 30) / N * sp) % (W + 30) - 15; wing = 1 if (f // 6) % 2 else -1
            d.line([x - 3, y0 - wing, x, y0], fill=BLK); d.line([x, y0, x + 3, y0 - wing], fill=BLK)
    return frame

def sc_sakura():
    r = random.Random(4); st = starfield(r, 14, 40)
    blobs = [(30, 34, 17), (50, 26, 15), (40, 16, 14), (62, 38, 11), (20, 44, 10)]
    dots = [(r.randrange(10, 72), r.randrange(6, 52), r.choice([ACC, ACH, PALE])) for _ in range(40)]
    pet = [dict(x=r.uniform(0, W), y=r.uniform(0, H), ph=r.uniform(0, 6.28), c=r.choice([ACH, PALE, ACC])) for _ in range(20)]
    fallen = [(r.randrange(W), r.randrange(84, 94), r.choice([ACH, PALE])) for _ in range(18)]
    def frame(f, d):
        bands(d, [SK1, SK2, SK3], 0, 84); twinkle(d, st, f); d.ellipse([140, 12, 152, 24], fill=PALE)
        d.rectangle([0, 82, W, H], fill=DARK)
        d.rectangle([35, 36, 40, 84], fill=BLK); d.line([38, 56, 56, 44], fill=BLK, width=2); d.line([37, 50, 24, 40], fill=BLK, width=2)
        for cx, cy, rad in blobs: d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=ACM)
        for x, y, c in dots: d.point((x, y), fill=c); d.point((x + 1, y), fill=c)
        for x, y, c in fallen: d.point((x, y), fill=c)
        for p in pet:
            y = (p["y"] + 2 * f) % H; x = p["x"] + 4 * sn(f, 1, p["ph"]) ; d.rectangle([int(x), int(y), int(x) + 1, int(y)], fill=p["c"])
    return frame

def sc_wood():
    r = random.Random(5); st = starfield(r, 24, 50)
    def frame(f, d):
        bands(d, [SK0, SK1, SK2], 0, 80); twinkle(d, st, f)
        d.rectangle([0, 80, W, H], fill=DARK)
        for x, h in ((18, 30), (34, 24), (132, 28), (150, 34), (164, 22)):
            d.polygon([(x - 9, 82), (x, 82 - h), (x + 9, 82)], fill=BLK)
        d.rectangle([62, 56, 106, 82], fill=DARK); d.polygon([(58, 57), (84, 38), (110, 57)], fill=BLK); d.rectangle([94, 36, 99, 48], fill=BLK)
        d.rectangle([70, 60, 84, 74], fill=ACD); win = [ACH, ACH, PALE, ACH, ACC, ACH][(f // 2) % 6]
        d.rectangle([72, 62, 82, 72], fill=win); d.line([77, 62, 77, 72], fill=BLK); d.line([72, 67, 82, 67], fill=BLK)
        d.rectangle([90, 66, 99, 82], fill=ACD)
        for i in range(8):
            t = ((f + i * 6) % N) / N; y = 36 - t * 32; x = 96 + 5 * math.sin(TAU * t * 1.5 + i); s = 1 + int(t * 3)
            d.ellipse([x - s, y - s, x + s, y + s], fill=DIM if t < .6 else ACD)
    return frame

def sc_redcell():
    r = random.Random(6); st = starfield(r, 18, 50)
    em = [dict(off=r.randrange(96), dx=r.uniform(-10, 10), ph=r.uniform(0, 6.28), c=r.choice([ACH, PALE, ACC])) for _ in range(16)]
    def flame(d, f, w, h, col, cx=85):
        j = 3 * sn(f, 2); b = 76
        d.polygon([(cx - w, b), (cx - w * .8, b - h * .45), (cx - w * .4, b - h * .7), (cx + j, b - h), (cx + w * .4, b - h * .65), (cx + w * .85, b - h * .4), (cx + w, b)], fill=col)
    def frame(f, d):
        bands(d, [SK0, SK1, SK2], 0, 76); twinkle(d, st, f); d.rectangle([0, 76, W, H], fill=DARK)
        d.ellipse([52, 70, 118, 90], fill=ACD)
        d.line([62, 82, 106, 74], fill=BLK, width=4); d.line([62, 74, 106, 82], fill=BLK, width=4)
        h = 24 + 4 * sn(f, 3) + 2 * sn(f, 5, 1)
        flame(d, f, 12, h, ACC); flame(d, f, 8, h * .72, ACH); flame(d, f, 4, h * .45, PALE)
        for e in em:
            y = 76 - (f * 2 + e["off"]) % 96; x = 85 + e["dx"] + 6 * math.sin(TAU * (f / N) + e["ph"])
            if y > 4: d.point((int(x), int(y)), fill=ACD if y < 30 else e["c"])
    return frame

def sc_monochrome():
    r = random.Random(7)
    back = []; x = -4
    while x < W: w = r.randrange(10, 18); back.append((x, w, r.randrange(30, 58))); x += w + 1
    front = []; x = -8
    while x < W: w = r.randrange(12, 22); front.append((x, w, r.randrange(14, 40))); x += w + 2
    wins = [(bx + 2 + 4 * i, H - bh + 3 + 5 * j, r.randrange(3)) for bx, bw, bh in back for i in range(max(1, (bw - 3) // 4)) for j in range(max(1, (bh - 4) // 5)) if r.random() < .45]
    rain = [dict(x=r.randrange(W), y=r.randrange(H), sp=r.choice([4, 6])) for _ in range(46)]
    def frame(f, d):
        bands(d, [SK0, SK1, SK2, SK3], 0, H)
        for bx, bw, bh in back: d.rectangle([bx, H - bh, bx + bw, H], fill=DARK)
        for x, y, p in wins: d.rectangle([x, y, x + 1, y + 1], fill=ACH if ((f // 8) + p) % 3 else DARK)
        for bx, bw, bh in front: d.rectangle([bx, H - bh, bx + bw, H], fill=BLK)
        for q in rain:
            y = (q["y"] + q["sp"] * f) % H; x = q["x"] - 0.25 * y; d.line([x + 1, y - 3, x, y], fill=DIM)
    return frame

def sc_neko():
    r = random.Random(8)
    rain = [dict(x=r.randrange(52, 120), y=r.randrange(H), sp=r.choice([4, 6])) for _ in range(26)]
    blds = [(52 + i * 11, r.randrange(8, 22)) for i in range(7)]
    def frame(f, d):
        d.rectangle([0, 0, W, H], fill=SK0)
        d.rectangle([50, 14, 121, 70], fill=SK2); d.rectangle([50, 38, 121, 70], fill=SK3)
        d.ellipse([100, 18, 112, 30], fill=PALE)
        for i, (x, h) in enumerate(blds):
            d.rectangle([x, 70 - h, x + 9, 70], fill=DARK)
            if i % 2 == 0: d.point((x + 3, 70 - h + 4), fill=ACH if (f // 12 + i) % 2 else DARK)
        for q in rain:
            y = 14 + (q["y"] + q["sp"] * f) % 56; x = q["x"] - 0.2 * (y - 14); d.line([x + 1, y - 3, x, y], fill=ACM)
        d.rectangle([50, 14, 121, 70], outline=BLK, width=2); d.line([85, 14, 85, 70], fill=BLK, width=2); d.line([50, 42, 121, 42], fill=BLK, width=2)
        d.rectangle([44, 70, 127, 76], fill=DARK); d.rectangle([0, 77, W, H], fill=BLK)
        d.ellipse([74, 54, 96, 76], fill=BLK); d.ellipse([78, 43, 94, 59], fill=BLK)
        d.polygon([(79, 48), (79, 38), (85, 45)], fill=BLK); d.polygon([(93, 48), (93, 38), (87, 45)], fill=BLK)
        for i in range(10):
            x = 96 + i * 1.6 + sn(f) * i * .5; y = 70 - i * 1.8; d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=BLK)
        h = 1 if 30 <= f <= 32 else 2
        for ex in (82, 88): d.rectangle([ex, 51, ex + 1, 51 + h - 1], fill=ACH)
    return frame

def sc_kyrie():
    r = random.Random(9)
    motes = [dict(rx=r.uniform(10, 46), ry=r.uniform(8, 30), cx=85 + r.uniform(-10, 10), cy=46 + r.uniform(-8, 8), ph=r.uniform(0, 6.28), k=r.choice([1, 1, 2]), c=r.choice([LIT, ACH, DIM])) for _ in range(14)]
    def frame(f, d):
        bands(d, [SK0, SK0], 0, H); fl = 2 * sn(f, 3) + sn(f, 5, 1)
        for rad, col in ((50, SK1), (38, SK2), (26, SK3), (16, ACD)):
            rr = rad + fl * (rad / 30); d.ellipse([85 - rr * 1.3, 46 - rr, 85 + rr * 1.3, 46 + rr], fill=col)
        d.rectangle([0, 82, W, H], fill=BLK); d.rectangle([76, 80, 94, 84], fill=DARK)
        d.rectangle([80, 52, 90, 80], fill=LIT); d.line([81, 52, 81, 60], fill=PALE); d.line([89, 52, 89, 66], fill=PALE)
        h = 9 + 2 * sn(f, 3) + sn(f, 5, 1); sway = 1.5 * sn(f, 2, 2)
        d.polygon([(81, 52), (85 + sway, 51 - h), (89, 52)], fill=ACC); d.polygon([(83, 52), (85 + sway * .7, 51 - h * .7), (87, 52)], fill=ACH); d.polygon([(84, 52), (85, 51 - h * .4), (86, 52)], fill=PALE)
        d.line([85, 51, 85, 54], fill=BLK)
        for m in motes:
            x = m["cx"] + m["rx"] * math.cos(TAU * f / N + m["ph"]); y = m["cy"] + m["ry"] * math.sin(m["k"] * TAU * f / N + m["ph"]); d.point((int(x), int(y)), fill=m["c"])
    return frame

SCENES = {"atmos": sc_atmos, "desert": sc_desert, "sunset": sc_sunset, "sakura": sc_sakura, "wood": sc_wood,
          "redcell": sc_redcell, "monochrome": sc_monochrome, "neko": sc_neko, "kyrie": sc_kyrie}
SCENE_NAMES = {"atmos": "night sky, drifting clouds, shooting star", "desert": "dunes, cactus, tumbleweed, sun",
               "sunset": "sinking sun over the sea, birds", "sakura": "cherry tree, falling petals",
               "wood": "cabin at night, flickering window, chimney smoke", "redcell": "campfire with rising embers",
               "monochrome": "rainy city skyline, blinking windows", "neko": "cat on a window sill in the rain",
               "kyrie": "candle flame with floating dust"}
ALIASES = {"campfire": "redcell", "cabin": "wood", "city": "monochrome", "cat": "neko", "candle": "kyrie", "night": "atmos"}

# ------------------------------------------------------------------- output
def render(scene_fn, pal):
    fn = scene_fn(); frames = []
    for f in range(N):
        im = Image.new("P", (W, H), SK1); im.putpalette(pal); fn(f, ImageDraw.Draw(im))
        frames.append(im.resize((W * S, H * S), Image.NEAREST))
    return frames

def backup(path):
    if not path.exists(): return None
    dest = path.with_name("loop.old.gif" if path.name == "loop.gif" else path.stem + ".old.gif")
    if dest.exists(): dest = dest.with_name(dest.stem + time.strftime("-%Y%m%d-%H%M%S") + dest.suffix)
    shutil.move(str(path), str(dest)); return dest

def main():
    ap = argparse.ArgumentParser(description="A different pixel-art loop.gif for every theme, in its own palette.")
    ap.add_argument("--themes", default=str(Path.home() / "viii-shell-2" / "themes"))
    ap.add_argument("--only"); ap.add_argument("--skip")
    ap.add_argument("--scene", help="force a scene (see --list) on the selected themes")
    ap.add_argument("--name", default="loop.gif", help="output file name inside each theme folder")
    ap.add_argument("--preview", metavar="PNG"); ap.add_argument("--list", action="store_true")
    ap.add_argument("--fps", type=int, default=12)
    a = ap.parse_args()
    if a.list:
        for k, v in SCENE_NAMES.items(): print(f"{k:<11} {v}")
        return
    td = Path(a.themes).expanduser()
    if not td.is_dir(): sys.exit(f"themes folder not found: {td}")
    only = {x.strip() for x in a.only.split(",")} if a.only else None
    skip = {x.strip() for x in a.skip.split(",")} if a.skip else set()
    names = sorted(d.name for d in td.iterdir() if (d / "palette.json").is_file())
    names = [n for n in names if (only is None or n in only) and n not in skip]
    if not names: sys.exit("no matching theme folders with a palette.json")
    order = list(SCENES)
    def scene_for(i, n):
        s = a.scene or n
        s = ALIASES.get(s, s)
        return s if s in SCENES else order[i % len(order)]
    if a.scene and ALIASES.get(a.scene, a.scene) not in SCENES: sys.exit("unknown scene, try --list")

    if a.preview:
        tw, th = 400, 225; cols = 3; rows = math.ceil(len(names) / cols)
        sheet = Image.new("RGB", (cols * tw, rows * (th + 22)), (20, 20, 20)); dd = ImageDraw.Draw(sheet)
        for i, n in enumerate(names):
            sc = scene_for(i, n); fn = SCENES[sc](); pal = make_palette(td / n / "palette.json")
            im = Image.new("P", (W, H), SK1); im.putpalette(pal); fn(14, ImageDraw.Draw(im))
            x, y = (i % cols) * tw, (i // cols) * (th + 22)
            sheet.paste(im.convert("RGB").resize((tw - 6, th - 2), Image.NEAREST), (x + 3, y + 1))
            dd.text((x + 8, y + th + 4), f"{n}  -  {sc}", fill=(230, 230, 230))
        out = Path(a.preview).expanduser(); out.parent.mkdir(parents=True, exist_ok=True); sheet.save(out)
        print(f"preview saved: {out}  (no gifs were written)"); return

    for i, n in enumerate(names, 1):
        t0 = time.time(); sc = scene_for(i - 1, n)
        frames = render(SCENES[sc], make_palette(td / n / "palette.json"))
        out = td / n / a.name; old = backup(out)
        frames[0].save(out, save_all=True, append_images=frames[1:], duration=round(1000 / a.fps), loop=0, optimize=False, disposal=1)
        if shutil.which("gifsicle"): subprocess.run(["gifsicle", "-O3", "--lossy=30", str(out), "-o", str(out)], stderr=subprocess.DEVNULL)
        note = f"  (previous kept as {old.name})" if old else ""
        print(f"[{i}/{len(names)}] {n:<12} {sc:<11} {out.stat().st_size / 1e3:6.0f} KB  {time.time() - t0:4.1f}s{note}")
    print("\nDone. Try: viii-theme <name>")

if __name__ == "__main__":
    main()
