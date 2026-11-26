#!/bin/sh
# record.sh: write the xz-utils recipe (the xz program: xz, unxz, xzcat) that
# onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. xz-utils is autoconf + libtool;
# configure and one verbose `make` run here ONCE, and what they decided
# travels in the recipe, PRE-GENERATED:
#   config.h (gen.tar)  what configure found
#   units               one line per object: obj, directory, source, its -D/-I
#                       flags (../lib/units-from-make.sh, from the make log)
#   link                the xz program's objects, liblzma.a expanded
# configure checks gcc as well as glibc, and the COMPILER answers are not
# pxx's. Those are given here as pxx's own, the result configure would reach
# with pxx as CC: no <immintrin.h>, no _mm_movemask_epi8 and no <cpuid.h>
# (they are gcc's headers, which the target does not have), and no CLMUL or
# ARM64 CRC code or hand-written assembler. Everything else configure finds
# (threads, Landlock, __builtin_assume_aligned, ...) pxx provides; a crtl
# change that removes one shows up as a compile error on site.
# The gcc build stays in $W/xz-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/xz/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=xz-5.6.3.tar.gz
"$T/../fetch.sh" "$TARBALL"
REF=$W/xz-ref
R=$W/recipe/xz
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
cd "$REF"
ac_cv_header_immintrin_h=no ac_cv_have_decl__mm_movemask_epi8=no ac_cv_header_cpuid_h=no \
  ./configure --disable-shared --disable-nls --disable-doc --disable-scripts \
    --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-clmul-crc --disable-arm64-crc32 --disable-assembler \
    > "$W/xz-configure.log" 2>&1
make -j3 V=1 > "$W/xz-build.log" 2>&1
[ -x src/xz/xz ] || { echo "record: gcc build made no xz" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
sh "$T/../lib/units-from-make.sh" "$REF" "$W/xz-build.log" xz \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-ARCHIVE' "$R/link" && { echo "record: an archive on the link line was not built in the log" >&2; exit 1; }
tar -cf "$R/gen.tar" config.h
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; xz links $(($(wc -w < "$R/link") - 1)) objects)"
