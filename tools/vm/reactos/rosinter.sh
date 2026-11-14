#!/bin/bash
# Interactive: resume the "ready" snapshot with no timeout, and optionally put
# some .exe files on a CD in the swap drive (no run.cmd, so the poller leaves
# it alone; they appear as D:). Drive it with rtype.py; screenshots land in
# $PXX_ROS_DIR/snap/live.png. Stop it with: roswait.py $SN cmd quit
# usage: rosinter.sh [file.exe...]     (runs in the foreground; background it)
set -u
. "$(dirname "$0")/roscommon.sh"
rm -f $SN/mon.sock
if [ $# -gt 0 ]; then
  rm -rf $SN/inter
  mkdir -p $SN/inter/cd
  cp "$@" $SN/inter/cd/
  xorriso -as mkisofs -quiet -V PXXI -o $SN/inter/inter.iso $SN/inter/cd 2>/dev/null || { echo "iso failed"; exit 1; }
  ( python3 $S/roswait.py $SN cmd "change swapcd $SN/inter/inter.iso" >/dev/null ) &
fi
rosqemu -loadvm ready
