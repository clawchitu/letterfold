#!/bin/zsh
# final.sh UDID DEVICE_DIR [LANGS] [SHOTS] — shoots the store set on MY sim (by UDID)
#   LANGS default "zh-Hans en ja ko"; SHOTS default all seven, e.g. "06-map" to re-shoot one
U=$1; DEV=$2; LANGS=(${=${3:-zh-Hans en ja ko}}); ONLY=(${=${4:-01-cover 02-stand 03-opener 04-shadow 05-crane-slip 06-map 07-letter}})
B=~/.tomo/workspace/tmp/lf-store; S=$B/shoot.sh; mkdir -p $B/raw
DONE="($(tr ' ' ',' < $B/done_ids.txt))"; SL="(stone,door,ink,tab,shadow,press,ride,glue,turn,wet,lamp,gate,roll,crane,fro)"
# 06-map: 卷三 with ch. 11 delivered and ch. 12 「三折」 under way (two of five)
MAPDONE="($(tr ' ' ',' < $B/done_ids.txt),over,fro,still,hover,past,park,home,hole)"; MAPSL="(stone,door,ink,tab,shadow,press,ride,glue,turn,wet,lamp,gate,roll,crane,fro,trifold)"
want() { (( ${ONLY[(Ie)$1]} )) }
for L in $LANGS; do
  O=$B/shots/$L/$DEV; mkdir -p $O
  xcrun simctl terminate $U com.haoqianglyu.letterfold 2>/dev/null; xcrun simctl spawn $U defaults delete com.haoqianglyu.letterfold 2>/dev/null
  want 01-cover && $S $U 01-cover 7 $L -screen cover -fold.doneIDs "()"
  want 02-stand && $S $U 02-stand 5 $L -startLevel 6 -startAngle 90 -noSlips YES -noOpener YES
  xcrun simctl spawn $U defaults delete com.haoqianglyu.letterfold 2>/dev/null
  want 03-opener && $S $U 03-opener 1.8 $L -resetProgress YES -noSlips YES -startLevel 14 -openerHold YES
  want 04-shadow && $S $U 04-shadow 5 $L -startLevel 14 -startAngle 125 -noSlips YES -noOpener YES
  want 05-crane-slip && $S $U 05-crane-slip 4 $L -screen objects -fold.doneIDs "$DONE" -fold.slipsSeen "$SL" -openSlip crane
  want 06-map && $S $U 06-map 4 $L -screen map -fold.doneIDs "$MAPDONE" -fold.slipsSeen "$MAPSL" -noOpener YES -noSlips YES
  want 07-letter && $S $U 07-letter 5 $L -screen letter -fold.doneIDs "$DONE"
  for f in $ONLY; do mv $B/raw/$f.png $O/$f.png; done
done
