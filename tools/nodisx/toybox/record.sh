#!/bin/sh
# record.sh: write the toybox recipe that onsite.sh replays on the target.
#
# HOST SIDE, and the only step that needs gcc and make. toybox's own build
# (scripts/make.sh) compiles helper programs with the host cc to generate its
# headers -- generated/{config,flags,globals,help,newtoys,tags,zhelp}.h -- from
# .config and the sources. Those headers are PRE-GENERATED HERE, on the build
# host, and travel in the recipe as gen.tar; the target never runs make.sh.
#
# The configuration is `make defconfig` plus CONFIG_GZIP (defconfig leaves it
# off; GUNZIP and ZCAT come with it), TR and XZCAT (below): the applets Nodisx's on-site builds use
# are all in it -- tar, gzip/zcat, bzcat, sed, sort, grep, cut, find, stat,
# sha256sum, readlink, cp, mv, chmod, mkdir, patch, mount, vi.
#
# Writes $NODISX_WORK/recipe/toybox/:
#   sources.list   tarball name and sha256 (unpacked --strip-components=1)
#   gen.tar        .config and generated/*.h, laid over the unpacked tree
#   compile.list   one compile per line: OBJ SRC FLAG... (the -I/-D/-U and
#                  -funsigned-char of gcc's own line; the rest is gcc tuning)
#   onsite.sh      the target's replay (a copy of the one beside this script)
#   RECIPE         the pxx commit this was recorded with
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/toybox/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=toybox-0.8.15.tar.gz
"$T/../fetch.sh" "$TARBALL"
REF=$W/toybox-ref
R=$W/recipe/toybox
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
cd "$REF"
make defconfig > "$W/toybox-defconfig.log" 2>&1
# GZIP (defconfig leaves it off), and from pending/ TR and XZCAT: the
# recipes' onsite.sh use tr, and xz's own source is a .tar.xz, so the
# bootstrap toybox must unpack it before any xz exists. Found by the first
# on-site build inside Rainyday (test-onsite-rainyday.sh), where the host's
# tr and xzcat were not there to hide it.
for c in GZIP TR XZCAT; do
  sed -i "s/^# CONFIG_$c is not set\$/CONFIG_$c=y/" .config
done
make oldconfig < /dev/null > "$W/toybox-oldconfig.log" 2>&1
for c in GZIP TR XZCAT; do
  grep -q "^CONFIG_$c=y" .config || { echo "record: CONFIG_$c did not stick" >&2; exit 1; }
done
# gcc reference build; its V=1 log holds every compile line
CPUS=${JOBS:-3} make V=1 toybox > "$W/toybox-gccbuild.log" 2>&1
[ -x toybox ] || { echo "record: the gcc build made no toybox" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
tar -cf "$R/gen.tar" .config generated/*.h
# compile.list from gcc's lines: `cc FLAGS -c SRC -o OBJ`
grep '^cc .* -c ' "$W/toybox-gccbuild.log" | while read -r line; do
  set -- $line
  shift
  flags= src= obj=
  while [ $# -gt 0 ]; do
    case $1 in
      -I|-D|-U) flags="$flags $1$2"; shift ;;
      -I*|-D*|-U*|-funsigned-char|-fsigned-char) flags="$flags $1" ;;
      -o) obj=$(basename "$2"); shift ;;
      *.c) src=$1 ;;
    esac
    shift
  done
  [ -n "$src" ] && [ -n "$obj" ] || { echo "record: cannot read: $line" >&2; exit 1; }
  echo "$obj $src$flags"
done > "$R/compile.list"
n=$(wc -l < "$R/compile.list")
[ "$n" -gt 100 ] || { echo "record: only $n compile lines" >&2; exit 1; }
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($n units)"
