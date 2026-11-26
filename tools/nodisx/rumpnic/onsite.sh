#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build rumpnic, Rainyday's driver for network
# cards through NetBSD's drivers (a rump kernel with wm, igc, re, rge and pcn,
# and the kernel under them), entirely with pxx, a POSIX shell and
# toybox-level tools (xzcat, tar, sha256sum). No gcc, binutils, buildrump.sh,
# NetBSD make, ar, nm, objcopy or python: the compile list was recorded on the
# build host (record.sh, from a gcc rump build) and comes in `units`; NetBSD's
# rename of the kernel's globals to rumpns_* is pxx's --rename-globals; and
# pxx --link takes the objects themselves, so no archive is made.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/rumpnic/onsite.sh /tmp/rumpnic [/mnt/target]
#
# DL: the directory holding src.tar.xz (sources.list names it and its sum).
# PXX: the pxx compiler (default `pxx`). JOBS: parallel compiles (default 2).
# RECIPE: the recipe directory (default: this script's). With DESTDIR,
# installs DESTDIR/sbin/rumpnic. Exit status 0 only if every unit compiled and
# linked. The sources are NetBSD's (BSD licences, NOTICE.netbsd beside the
# driver) and Rainyday's (MIT).
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj"
xzcat "$DL/$name" | tar -xf - -C "$WORK/src"
S=$WORK/src
KEEP=rump,RUMP,__,_GLOBAL_OFFSET_TABLE,.TOC.

# one compile: the unit line's words, @T@ and @R@ made into paths
unit() {
  obj=$1; kind=$2; ren=$3; dir=$4; src=$5; shift 5
  o=$WORK/obj/$obj
  set -- $(echo "$*" | sed "s|@T@|$S/t|g; s|@R@|$S/r|g")
  dir=$(echo "$dir" | sed "s|@T@|$S/t|; s|@R@|$S/r|")
  src=$(echo "$src" | sed "s|@T@|$S/t|; s|@R@|$S/r|")
  case $kind in
    h) set -- --threadsafe "$@" ;;
  esac
  if [ "$ren" = 1 ]; then set -- --rename-globals=rumpns_ --rename-globals-keep=$KEEP "$@"; fi
  ( cd "$dir" && "$PXX" --emit-obj "$@" "$src" "$o" ) > "$o.log" 2>&1 || : > "$o.fail"
}

i=0
while read -r line; do
  # shellcheck disable=SC2086 -- a unit line is words
  unit $line &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done < "$R/units"
wait
n=0
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  n=$((n + 1))
done
[ "$n" = 0 ] || exit 1

list=
while read -r obj rest; do list="$list $WORK/obj/$obj"; done < "$R/units"
# shellcheck disable=SC2086
"$PXX" --link --threadsafe -o "$WORK/rumpnic" $list > "$WORK/link.log" 2>&1 \
  || { echo "onsite: pxx --link failed:" >&2; tail -20 "$WORK/link.log" >&2; exit 1; }
echo "onsite: $WORK/rumpnic ($(wc -l < "$R/units") objects)"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/sbin"
  cp "$WORK/rumpnic" "$DEST/sbin/rumpnic"
  chmod 755 "$DEST/sbin/rumpnic"
  echo "onsite: installed into $DEST"
fi
