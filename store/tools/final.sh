#!/bin/zsh
# final.sh UDID DEVICE_DIR — shoots the store set in zh-Hans and en on MY sim (by UDID)
U=$1; DEV=$2; B=~/.tomo/workspace/tmp/lf-store; S=$B/shoot.sh
DONE="($(tr ' ' ',' < $B/done_ids.txt))"; SL="(stone,door,ink,tab,shadow,press,ride,glue,turn,wet,lamp,gate,roll,crane,fro)"
for L in zh-Hans en; do
  O=$B/shots/$L/$DEV; mkdir -p $O
  xcrun simctl terminate $U com.haoqianglyu.letterfold 2>/dev/null; xcrun simctl spawn $U defaults delete com.haoqianglyu.letterfold 2>/dev/null
  $S $U 01-cover 7 $L -screen cover -fold.doneIDs "()"
  $S $U 02-stand 5 $L -startLevel 6 -startAngle 90 -noSlips YES -noOpener YES
  xcrun simctl spawn $U defaults delete com.haoqianglyu.letterfold 2>/dev/null
  $S $U 03-opener 1.8 $L -noSlips YES -startLevel 14 -openerHold YES
  $S $U 04-shadow 5 $L -startLevel 14 -startAngle 125 -noSlips YES -noOpener YES
  $S $U 05-crane-slip 4 $L -screen objects -fold.doneIDs "$DONE" -fold.slipsSeen "$SL" -openSlip crane
  $S $U 06-map 4 $L -screen map -fold.doneIDs "$DONE" -fold.slipsSeen "$SL" -noOpener YES -noSlips YES
  $S $U 07-letter 5 $L -screen letter -fold.doneIDs "$DONE"
  for f in 01-cover 02-stand 03-opener 04-shadow 05-crane-slip 06-map 07-letter; do mv $B/raw/$f.png $O/$f.png; done
done
