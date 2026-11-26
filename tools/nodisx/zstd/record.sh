#!/bin/sh
# record.sh: write the zstd recipe (zstd, unzstd, zstdcat) that onsite.sh
# replays on the target.
#
# HOST SIDE, the only step that needs gcc. zstd has no configure: its
# Makefile probes for zlib, lzma and lz4 by compiling test programs, and those
# answers are the HOST's. They are given here as the target's: no zlib, lzma or
# lz4 (zstd reads and writes .zst only; xz and gzip are separate tools), no
# hand-written assembler (ZSTD_NO_ASM: huf_decompress_amd64.S is gas syntax),
# and pthreads on (pxx --threadsafe), so -T works. `make -C programs V=1` runs
# once; its log gives the recipe through ../lib/units-from-make.sh:
#   units   one line per object: obj, directory, source, its -D/-I flags
#   link    the zstd program's objects
# Nothing is generated, so there is no gen.tar.
# The gcc build stays in $W/zstd-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/zstd/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=zstd-1.5.6.tar.gz
"$T/../fetch.sh" "$TARBALL" > /dev/null
REF=$W/zstd-ref
R=$W/recipe/zstd
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
make -C "$REF/programs" -j3 zstd V=1 ZSTD_NO_ASM=1 HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 HAVE_PTHREAD=1 \
  > "$W/zstd-build.log" 2>&1
[ -x "$REF/programs/zstd" ] || { echo "record: gcc build made no zstd" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
# the Makefile names lib/ sources by absolute path; every unit compiles in
# programs/, so the tree's root is ../ from there
sh "$T/../lib/units-from-make.sh" "$REF" "$W/zstd-build.log" zstd \
  | sed "s| $REF/| ../|g" \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q "$REF" "$R/units" "$R/link" && { echo "record: a host path is left in the recipe" >&2; exit 1; }
awk '$2 != "programs" { bad = 1 } END { exit bad }' "$R/units" || { echo "record: a unit outside programs/" >&2; exit 1; }
grep -q 'MISSING-ARCHIVE' "$R/link" && { echo "record: an archive on the link line was not built in the log" >&2; exit 1; }
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; zstd links $(($(wc -w < "$R/link") - 1)) objects)"
