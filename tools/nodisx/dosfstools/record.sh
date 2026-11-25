#!/bin/sh
# record.sh: write the dosfstools recipe (mkfs.fat, fsck.fat, fatlabel) that
# onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. dosfstools is autoconf; its
# configure runs here ONCE, with gcc, and what it decided travels in the
# recipe, PRE-GENERATED:
#   flags     the -D list configure settled on (DEFS in src/Makefile)
#   units     one line per program: the program, then its .c files (from the
#             link lines automake writes)
#   gen.tar   src/version.h, which configure writes from version.h.in
# configure checks the build host's glibc; pxx's crtl provides what the flags
# say is there (every unit compiles, and dosfstools' own `make check` passes
# on the pxx binaries, see test.sh). The gcc build stays in $W/dosfstools-ref
# for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dosfstools/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=dosfstools-4.2.tar.gz
PROGS="mkfs.fat fsck.fat fatlabel"
"$T/../fetch.sh" "$TARBALL"
REF=$W/dosfstools-ref
R=$W/recipe/dosfstools
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
cd "$REF"
./configure --without-udev --disable-compat-symlinks > "$W/dosfstools-configure.log" 2>&1
make -j3 > "$W/dosfstools-build.log" 2>&1

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
sed -n 's/^DEFS = //p' src/Makefile > "$R/flags"
[ -s "$R/flags" ] || { echo "record: no DEFS in src/Makefile" >&2; exit 1; }
# automake's link line names each object <prog>-<unit>.o (or plain <unit>.o),
# under the unit's directory: blkdev/mkfs_fat-blkdev.o is blkdev/blkdev.c
: > "$R/units"
for p in $PROGS; do
  make -s -C src clean > /dev/null
  line=$(make -n -C src "$p" 2>/dev/null | grep -E -- "-o $p( |\$)" | tail -1)
  [ -n "$line" ] || { echo "record: no link line for $p" >&2; exit 1; }
  pre=$(echo "$p" | tr . _)-
  srcs=
  for w in ${line#*-o $p}; do
    case $w in *.o) ;; *) continue ;; esac
    d=$(dirname "$w"); b=$(basename "$w" .o); b=${b#"$pre"}
    case $d in .) srcs="$srcs $b.c" ;; *) srcs="$srcs $d/$b.c" ;; esac
  done
  echo "$p$srcs" >> "$R/units"
done
make -j3 > /dev/null 2>&1    # the reference binaries again, after the cleans
tar -cf "$R/gen.tar" src/version.h
for p in $PROGS; do [ -x "src/$p" ] || { echo "record: gcc build made no $p" >&2; exit 1; }; done
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R"
cat "$R/units"
