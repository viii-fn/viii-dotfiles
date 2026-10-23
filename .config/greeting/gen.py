#!/usr/bin/env python3
import sys, subprocess
from PIL import Image, ImageDraw, ImageFont

char = sys.argv[1] if len(sys.argv) > 1 else "λ"
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 24   # width in terminal cells

font_path = subprocess.check_output(["fc-match", "-f", "%{file}", "sans:bold"]).decode()
font = ImageFont.truetype(font_path, 400)

img = Image.new("L", (700, 700), 0)
ImageDraw.Draw(img).text((100, 50), char, font=font, fill=255)
img = img.crop(img.getbbox())

w = cols * 2
h = round(img.height * w / img.width)
h += (-h) % 4
img = img.resize((w, h), Image.LANCZOS)
px = img.load()

dots = [(0,0,0x01),(0,1,0x02),(0,2,0x04),(1,0,0x08),(1,1,0x10),(1,2,0x20),(0,3,0x40),(1,3,0x80)]
for y in range(0, h, 4):
    row = ""
    for x in range(0, w, 2):
        bits = sum(b for dx, dy, b in dots if px[x+dx, y+dy] > 110)
        row += chr(0x2800 + bits)
    print(row)
