#!/bin/bash
# Run --os=windows test programs inside ReactOS and compare with Linux.
# Builds each one twice (Linux, Windows), puts the .exe files and a run.cmd
# on a small ISO, resumes the "ready" snapshot (rossnap.sh), inserts the ISO
# in the swap CD drive; the StartUp poller runs run.cmd and powers off.
# Results come off the data disk; the next resume resets it.
# usage: rosbatch.sh [-t seconds] [-e VAR=VALUE]... [-f file]... test...
#   -f: put this file on the CD next to the programs (a DLL they import:
#   the loader looks in the program's own directory first).
#   test: a name under test/ (".pas" assumed without an extension) or an
#   absolute path; ":ts" appended builds with --threadsafe. A program with
#   no Linux build (Windows-only probe) runs and is shown, not compared.
# Each program gets an empty stdin; \tmp exists on the data drive (the
# current drive, so /tmp/x is \tmp\x). Output written before a timeout can
# be lost (ReactOS had not flushed it); run a hanging program by hand with
# rosinter.sh. Typical batch: 10 s plus the programs' own time.
set -u
. "$(dirname "$0")/roscommon.sh"
P=${PXX:-$ROOT/compiler/pascal26}
T=$ROOT/test
secs=600
envs=""
files=""
while :; do
  case "${1:-}" in
    -t) secs=$2; shift 2;;
    -e) envs="$envs$2 "; shift 2;;
    -f) files="$files$2 "; shift 2;;
    *) break;;
  esac
done
qemu-img snapshot -l $SN/data.qcow2 2>/dev/null | grep -q ' ready ' || { echo "no snapshot: run rossnap.sh"; exit 1; }
B=$SN/batch
rm -rf $B; mkdir -p $B/cd $B/want $B/got
for f in $files; do cp "$f" $B/cd/ || exit 1; done
# the 2 s pause: right after a resume the guest clock is still settling
printf '@echo off\r\nset IN=%%1\r\nset OUT=\r\nfor %%%%d in (C D E F G H I) do if exist %%%%d:\\pxxmark set OUT=%%%%d:\r\nif "%%OUT%%"=="" goto :eof\r\n%%OUT%%\r\ncd \\\r\ntimeout /t 2 /nobreak > nul\r\nif not exist \\tmp mkdir \\tmp\r\n' > $B/cd/run.cmd
for e in $envs; do printf 'set %s\r\n' "$e" >> $B/cd/run.cmd; done
i=0
: > $B/map.txt
for t in "$@"; do
  flags=""; src=$t
  case $t in *:ts) flags="--threadsafe"; src=${t%:ts};; esac
  case ${src##*/} in *.*) ;; *) src=$src.pas;; esac
  sp=$T/$src; case $src in /*) sp=$src;; esac
  i=$((i+1)); n=t$i
  linux=1; $P $flags $sp $B/$n.lx >/dev/null 2>&1 || linux=0
  $P $flags --os=windows $sp $B/cd/$n.exe >/dev/null 2>&1 || { echo "build fail win $src"; continue; }
  if [ $linux = 1 ]; then
    (cd $B && ./$n.lx < /dev/null > $B/want/$n.out 2>&1; echo "exit=$?" >> $B/want/$n.out)
  else
    echo "(windows only)" > $B/want/$n.out
  fi
  echo "$n $src" >> $B/map.txt
  printf 'echo %s > %s.started\r\n%%IN%%\\%s.exe < nul > %s.out 2>&1\r\n>>%s.out echo exit=%%errorlevel%%\r\n' $n $n $n $n $n >> $B/cd/run.cmd
done
printf 'echo done > alldone.txt\r\n' >> $B/cd/run.cmd
rm -f $B/cd/*.map
xorriso -as mkisofs -quiet -J -joliet-long -V PXXB -o $B/batch.iso $B/cd 2>/dev/null || { echo "iso failed"; exit 1; }
start=$(date +%s)
rm -f $SN/mon.sock
timeout $secs bash -c ". '$S/roscommon.sh'; rosqemu -loadvm ready" &
QP=$!
python3 $S/roswait.py $SN cmd "change swapcd $B/batch.iso" >/dev/null
wait $QP; rc=$?
echo "vm $(( $(date +%s) - start ))s$([ $rc = 124 ] && echo ' TIMEOUT')"
qemu-img convert -O raw $SN/data.qcow2 $B/data.raw
mcopy -i $B/data.raw@@1M -n '::/*' $B/got/ 2>/dev/null
rm -f $B/data.raw
[ -f $B/got/alldone.txt ] || echo "run.cmd did not finish"
pass=0; fail=0
while read n src; do
  if [ ! -f $B/got/$n.out ]; then echo "NORUN $src"; fail=$((fail+1)); continue; fi
  if grep -qx '(windows only)' $B/want/$n.out; then
    echo "SHOW $src"; tr -d '\r' < $B/got/$n.out | sed 's/^/    /'; continue
  fi
  if diff <(tr -d '\r' < $B/got/$n.out) $B/want/$n.out >/dev/null; then pass=$((pass+1)); echo "PASS $src"
  else fail=$((fail+1)); echo "FAIL $src"; diff <(tr -d '\r' < $B/got/$n.out) $B/want/$n.out | head -8 | sed 's/^/    /'; fi
done < $B/map.txt
echo "pass=$pass fail=$fail"
