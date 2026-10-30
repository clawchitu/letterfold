#!/usr/bin/env python3
"""Captioned variants: the raw shot scaled to 84% on the app's paper colour, one quiet line above it.
Usage: caption.py SHOTS_DIR   (reads <SHOTS>/<lang>/<device>/NN-*.png, writes <SHOTS>/<lang>/<device>-captioned/)"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
CAP = {
 "zh-Hans": {"01": "一本合上才能读懂的书", "02": "立起来，纸就是桥", "03": "每一章，纸会做一件新的事",
             "04": "灯在纸后面，影子也是路", "05": "遇到的东西，都夹在书里", "06": "三卷十二章，从左岸到右岸",
             "07": "每章末尾，一封对岸来信"},
 "ja":      {"01": "閉じてはじめて読める本", "02": "立てれば、紙は橋になる", "03": "章ごとに、紙がひとつ新しいことをする",
             "04": "紙の後ろに灯り、影も道になる", "05": "出会ったものは、みな本に挟んである", "06": "三巻十二章、左岸から右岸へ",
             "07": "章の終わりに、向こう岸からの手紙"},
 "ko":      {"01": "덮어야 읽히는 책", "02": "세우면, 종이는 다리가 된다", "03": "장마다, 종이가 새로운 일을 하나 한다",
             "04": "종이 뒤의 등불, 그림자도 길이 된다", "05": "만난 것은 모두 책에 끼워 둔다", "06": "세 권 열두 장, 강가에서 강가로",
             "07": "장이 끝날 때마다, 건너편 강가에서 온 편지"},
 "en":      {"01": "A book you read by closing it", "02": "Stand the page up: a bridge", "03": "Each chapter, one new thing paper does",
             "04": "Lamp behind the page: shadows are paths", "05": "Everything you meet is tucked in the book", "06": "Three books, twelve chapters, bank to bank",
             "07": "A letter from the other bank"},
}
PAPER, INK, VERMILION = (241, 236, 228), (33, 30, 26), (192, 57, 43)
SONGTI, NEWYORK = "/System/Library/Fonts/Supplemental/Songti.ttc", "/System/Library/Fonts/NewYork.ttf"
MINCHO, MYUNGJO = "/System/Library/Fonts/ヒラギノ明朝 ProN.ttc", "/System/Library/Fonts/Supplemental/AppleMyungjo.ttf"

def font(lang, size):
    if lang == "ja": return ImageFont.truetype(MINCHO, size, index=1)   # W6
    if lang == "ko": return ImageFont.truetype(MYUNGJO, size)
    if lang.startswith("zh"):
        for i in range(12):
            try:
                f = ImageFont.truetype(SONGTI, size, index=i)
                if f.getname() == ("STSongti-SC", "Bold") or "Bold" in f.getname()[1] and "SC" in f.getname()[0]: return f
            except OSError: break
        return ImageFont.truetype(SONGTI, size, index=0)
    return ImageFont.truetype(NEWYORK, size)

def render(src, dst, text, lang):
    shot = Image.open(src).convert("RGB"); W, H = shot.size
    s = 0.84; sw, sh = int(W * s), int(H * s)
    canvas = Image.new("RGB", (W, H), PAPER); top = H - sh - int(H * 0.035)
    small = shot.resize((sw, sh), Image.LANCZOS)
    # soft frame: hairline + shadow
    d = ImageDraw.Draw(canvas); x0 = (W - sw) // 2
    for k in range(18, 0, -2): d.rounded_rectangle([x0 - k, top - k // 2, x0 + sw + k, top + sh + k], radius=int(W * .06) + k, fill=tuple(c - (20 - k) // 3 for c in PAPER))
    mask = Image.new("L", (sw, sh), 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], radius=int(W * .06), fill=255)
    canvas.paste(small, (x0, top), mask)
    size = int(W * (0.058 if lang[:2] in ("zh", "ja", "ko") else 0.052)); f = font(lang, size)
    while d.textlength(text, font=f) > W * 0.86: size -= 2; f = font(lang, size)
    ty = int(top * 0.42) - size // 2
    d.text((W / 2, ty), text, font=f, fill=INK, anchor="mm")
    d.line([(W / 2 - W * .03, ty + size * 1.0), (W / 2 + W * .03, ty + size * 1.0)], fill=VERMILION, width=max(3, W // 330))
    canvas.save(dst)

root = sys.argv[1]
for lang in CAP:
    for dev in ("iphone69",):   # 1.0 is iPhone only
        src_dir = os.path.join(root, lang, dev)
        if not os.path.isdir(src_dir): continue
        out = os.path.join(root, lang, dev + "-captioned"); os.makedirs(out, exist_ok=True)
        for fn in sorted(os.listdir(src_dir)):
            if fn.endswith(".png"): render(os.path.join(src_dir, fn), os.path.join(out, fn), CAP[lang][fn[:2]], lang)
print("done")
