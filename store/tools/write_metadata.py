#!/usr/bin/env python3
"""Writes store/metadata/<locale>/*.txt (fastlane-deliver layout) and checks every App Store limit.
Run: python3 store/tools/write_metadata.py  (exits 1 if anything is over)."""
import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "metadata")
LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "description": 4000, "keywords": 100, "release_notes": 4000}

M = {
"zh-Hans": dict(
name="折信 Letterfold",
subtitle="一本合上才能读懂的书",
promotional_text="左岸的信，要越过折痕送到右岸。合上、立起、斜着停在半空——两页相触的那一下，路就接上了。",
keywords="解谜,折纸,益智,烧脑,镜像,对称,纸,影子,治愈,独立游戏,禅,极简",
release_notes="第一版。三卷十二章，七十余关。\n信，送到了。",
description="""河很宽，纸很薄。
我把想说的话折了四次，等你合上它的那天。

《折信》是一本解谜的书。左岸的人想把一封信送到右岸，中间隔着一条河——就是书页中间那道折痕。

用手指拖动书页：合上，立起，或者斜着停在半空。合上的时候两页相触，这一页的路会落到对页的镜像位置；立起来，纸会站成一座桥；灯在纸后面的时候，石头的影子也能走。

每一关都很小，只有几行几列，只为一个「啊」的瞬间。没有计时，没有分数，也没有教你怎么做的说明文字——每一条规则都是纸本来就会做的事：折、压、印、洇、透光、投影。

· 三卷十二章，七十余关，另有几封暗信
· 每一章的末尾，有一封从对岸寄来的信
· 物件笺：遇到的每一样东西都夹在书里，随时可以翻看
· 所有声音都在演奏时实时合成：古琴、箫、木声、纸声
· 完整支持旁白（VoiceOver）、按钮操作、高对比、超大格子、减弱动态效果，还有一种用音高和左右声道「听」棋盘的声音模式
· 简体中文、English

免费。没有广告，没有内购，不需要账号，不收集任何数据。

慢慢来。信不急。"""),
"en-US": dict(
name="Letterfold",
subtitle="Close the book to read it",
promotional_text="A letter has to cross the river in the middle of the page. Close the book, stand it up, let it rest halfway — the moment the two pages touch, the path joins.",
keywords="puzzle,fold,origami,paper,mirror,crease,letter,logic,zen,minimal,brain,shadow,indie,calm,book",
release_notes="The first edition. Three books, twelve chapters, more than seventy puzzles.\nThe letter has arrived.",
description="""The river is wide; the paper, thin.
I folded what I meant to say four times, for the day you close it.

Letterfold is a puzzle book. Someone on the left bank is trying to get a letter to the right bank, and between them runs a river: the crease down the middle of the page.

Drag the page with a finger. Close it, stand it up, or let it rest halfway. When the book shuts, the two pages touch, and a path on one lands mirrored on the other. Stood upright, the paper becomes a bridge. With a lamp behind the page, even a stone's shadow can be walked on.

Each puzzle is small, a few rows and a few columns, and turns on a single moment of seeing. No timers, no scores, no instructions in words. Every rule is something paper already does: fold, press, print, bleed, let the light through, cast a shadow.

· Three books, twelve chapters, more than seventy puzzles, and a few hidden letters
· A letter from the other bank at the end of every chapter
· Object slips: everything you meet is tucked into the book to read again
· Every sound is synthesised as you play: guqin, xiao, wood and paper
· Full VoiceOver support, button controls, high contrast, a larger grid, Reduce Motion, and a sound mode that lets you hear the board by pitch and position
· Simplified Chinese and English

Free. No ads, no in-app purchases, no account, and no data collected.

Take your time. The letter can wait."""),
"ja": dict(  # polished 2026-10-29 against fold-proto docs/l10n-glossary.md (in-app terms: ページ・マス・すき間・折り目・灯り・隠し手紙・しおり)
name="折り文 Letterfold",
subtitle="閉じてはじめて読める本",
promotional_text="左岸の手紙は、ページの真ん中の折り目を越えて右岸へ。閉じる、立てる、途中で止める——二つのページがふれた一瞬、道がつながる。",
keywords="パズル,折り紙,紙,本,手紙,鏡,影,謎解き,癒し,インディー,ミニマル,禅",
release_notes="第一版。三巻十二章、七十を超えるパズル。\n手紙が届いた。",
description="""川は広く、紙は薄い。
言いたいことを四つに折って、きみが閉じる日を待っている。

『折り文』は、謎を解く本です。左岸の人が右岸へ手紙を届けようとしています。そのあいだを流れる川は、ページの真ん中の折り目です。

指でページをドラッグして、閉じる、立てる、途中で止める。閉じると二つのページがふれ合い、こちらの道が向かいのページの鏡の位置に重なります。立てれば紙は橋になり、紙の後ろに灯りがあれば、石の影の上も歩けます。

どのパズルも小さく、数行数列だけ。あるのは「あ」と気づく一瞬です。タイマーも、スコアも、言葉での説明もありません。ルールはすべて、紙がもともとすること——折る、押す、写す、滲む、光を通す、影を落とす。

· 三巻十二章、七十を超えるパズルと、いくつかの隠し手紙
· 章の終わりごとに、向こう岸からの手紙
· 物のしおり：出会ったものはすべて本に挟まれ、いつでも読み返せます
· 音はすべて演奏のたびに合成：古琴、簫、木と紙の音
· VoiceOver、ボタン操作、高コントラスト、大きなマス、視差効果を減らす、そして音の高さと左右で盤面を「聴く」サウンドモードに対応
· 日本語・简体中文・English・한국어

無料。広告なし、App内課金なし、アカウント不要、データの収集もありません。

ゆっくりどうぞ。手紙は急ぎません。"""),
"ko": dict(  # polished 2026-10-29 against fold-proto docs/l10n-glossary.md (in-app terms: 페이지·칸·틈·접는 선·등불·숨은 편지·쪽지; 덮다 is the book verb here, 닫기 in-app)
name="접은 편지 Letterfold",
subtitle="덮어야 읽히는 책",
promotional_text="왼쪽 강가의 편지가 페이지 한가운데의 접는 선을 건너 오른쪽 강가로 갑니다. 덮고, 세우고, 반쯤에서 멈추고—두 페이지가 맞닿는 순간, 길이 이어집니다.",
keywords="퍼즐,종이접기,종이,책,편지,거울,그림자,힐링,인디,미니멀,두뇌",
release_notes="첫 판. 세 권, 열두 장, 일흔 개가 넘는 퍼즐.\n편지가 도착했다.",
description="""강은 넓고, 종이는 얇다.
하고 싶은 말을 네 번 접어, 네가 책을 덮는 날을 기다린다.

『접은 편지』는 퍼즐 책입니다. 왼쪽 강가의 사람이 오른쪽 강가로 편지를 보내려 합니다. 그 사이를 흐르는 강은 페이지 한가운데의 접는 선입니다.

손가락으로 페이지를 끌어 덮고, 세우고, 반쯤에서 멈춰 두세요. 책을 덮으면 두 페이지가 맞닿고, 이쪽의 길이 맞은편 페이지의 거울 자리에 겹칩니다. 세우면 종이는 다리가 되고, 종이 뒤에 등불이 있으면 돌의 그림자 위도 걸을 수 있습니다.

퍼즐은 모두 작습니다. 몇 행, 몇 열, 그리고 "아" 하고 알아차리는 한순간. 타이머도, 점수도, 글로 된 설명도 없습니다. 모든 규칙은 종이가 원래 하는 일입니다: 접고, 누르고, 찍고, 번지고, 빛을 통과시키고, 그림자를 드리우는 것.

· 세 권, 열두 장, 일흔 개가 넘는 퍼즐과 몇 통의 숨은 편지
· 장이 끝날 때마다, 건너편 강가에서 온 편지
· 물건 쪽지: 만난 것은 모두 책에 끼워 두고 언제든 다시 읽을 수 있습니다
· 모든 소리는 연주할 때마다 합성됩니다: 고금, 퉁소, 나무와 종이 소리
· VoiceOver, 버튼 조작, 고대비, 큰 칸, 동작 줄이기, 그리고 음높이와 좌우로 판을 "듣는" 소리 모드 지원
· 한국어·简体中文·English·日本語

무료. 광고 없음, 앱 내 구입 없음, 계정 없음, 데이터 수집 없음.

천천히 하세요. 편지는 급하지 않습니다."""),
}

def measure(field, text):
    return len(text.encode("utf-8")) if field == "keywords" else len(text)

bad = False
for loc, fields in M.items():
    os.makedirs(os.path.join(ROOT, loc), exist_ok=True)
    for f, t in fields.items():
        n, lim = measure(f, t), LIMITS[f]
        extra = ""
        if f == "keywords":
            if " " in t or ", " in t: extra = " SPACES!"; bad = True
            extra += f" ({len(t)} chars)"
        flag = "OK " if n <= lim else "OVER"
        if n > lim: bad = True
        print(f"{flag} {loc:8} {f:17} {n:4}/{lim}{' bytes' if f=='keywords' else ''}{extra}")
        with open(os.path.join(ROOT, loc, f + ".txt"), "w") as fh: fh.write(t + "\n")
sys.exit(1 if bad else 0)
