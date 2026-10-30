#!/bin/zsh
# shoot.sh UDID NAME WAIT LANG args...  — launch Letterfold with launch args on MY sim only, screenshot
U=$1; N=$2; W=$3; L=$4; shift 4
xcrun simctl terminate $U com.haoqianglyu.letterfold 2>/dev/null
xcrun simctl launch $U com.haoqianglyu.letterfold -AppleLanguages "($L)" -set.lang "" "$@" >/dev/null
perl -e "select(undef,undef,undef,$W)"
xcrun simctl io $U screenshot ~/.tomo/workspace/tmp/lf-store/raw/$N.png 2>/dev/null
