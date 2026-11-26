#!/bin/sh
# record.sh: write the bzip2 recipe (bzip2, bunzip2, bzcat, bzip2recover) that
# onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. bzip2 has no configure: a plain
# Makefile with one flag set (-D_FILE_OFFSET_BITS=64). It runs once here, and
# its log gives the recipe:
#   units   one line per object: obj, directory, source, its -D/-I flags
#   link    bzip2's and bzip2recover's objects, libbz2.a expanded
# Nothing is generated, so there is no gen.tar. The bzip2 Makefile compiles
# `gcc ... -c x.c` with no -o, which lib/units-from-make.sh does not read;
# the awk below is that script's logic for this one Makefile.
# The gcc build stays in $W/bzip2-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/bzip2/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=bzip2-1.0.8.tar.gz
"$T/../fetch.sh" "$TARBALL" > /dev/null
REF=$W/bzip2-ref
R=$W/recipe/bzip2
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
( cd "$REF" && make -j3 bzip2 bzip2recover ) > "$W/bzip2-build.log" 2>&1
[ -x "$REF/bzip2" ] && [ -x "$REF/bzip2recover" ] || { echo "record: gcc build made no bzip2" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
awk -v u="$R/units" -v l="$R/link" '
$1 == "gcc" || $1 == "cc" {
  isc = 0; src = ""; out = ""; flags = ""; objs = ""; libs = ""
  for (i = 2; i <= NF; i++) {
    if ($i == "-c") isc = 1
    else if ($i == "-o") out = $(++i)
    else if ($i ~ /^-[DUI]./) flags = flags " " $i
    else if ($i ~ /\.c$/) src = $i
    else if ($i ~ /\.o$/) objs = objs " " $i
    else if ($i == "-lbz2") libs = libs " LIBBZ2"
  }
  if (isc && src != "") { o = src; sub(/\.c$/, ".o", o); print o " . " src flags > u; next }
  if (out != "") { sub(/LIBBZ2/, "", libs); link[++nl] = out objs (libs != "" ? " @libbz2" : "") }
  next
}
$1 == "ar" { for (i = 4; i <= NF; i++) if ($i ~ /\.o$/) members = members " " $i; next }
END {
  for (i = 1; i <= nl; i++) { s = link[i]; sub(/ @libbz2/, members, s); print s > l }
}' "$W/bzip2-build.log"
[ "$(wc -l < "$R/link")" = 2 ] || { echo "record: expected two link lines, got $(wc -l < "$R/link")" >&2; exit 1; }
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; $(cut -d' ' -f1 "$R/link" | tr '\n' ' '))"
