#!/bin/sh
# test.sh: PASS/FAIL for the bzip2 recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs bzip2's own `make test` (three reference files, compressed at -1..-3
#     and decompressed, also with -s) with the pxx bzip2 in place of gcc's;
#  2. compresses a tarball, random data, an empty file and a run of zeros with
#     both builds at -1, -5 and -9 and compares the .bz2 files byte for byte,
#     then decompresses each with the other build;
#  3. `-t` on a good and a corrupt file, bzcat over two concatenated streams,
#     and bzip2recover on a truncated file, all compared with gcc's builds;
#  4. decompresses every .tar.bz2 the Nodisx and Path B downloads hold.
# PASS is all four: every output and exit status identical to gcc's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/bzip2/test.sh
# Needs record.sh to have run, and make (host only).
set -eu
export LC_ALL=C
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/bzip2
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/bzip2-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/bzip2-ref
G=$REF/bzip2
Q=$O/work/bzip2
fail=0
same() {  # label a b
  if [ "$2" = "$3" ]; then :; else echo "$1: DIFFERS"; fail=1; fi
}

# 1. the suite
mkdir -p "$O/suite"
cp -a "$REF/." "$O/suite/"
cp "$Q" "$O/suite/bzip2"; touch "$O/suite/bzip2"
if ( cd "$O/suite" && make test ) > "$O/check.log" 2>&1; then echo "bzip2 make test: pass"; else echo "bzip2 make test: FAIL"; fail=1; fi
cmp -s "$Q" "$O/suite/bzip2" || { echo "test: make rebuilt bzip2"; fail=1; }

# 2. compression byte for byte, and each build reads the other's output
I=$O/in
mkdir -p "$I"
zcat "$W/dl/$(cut -d' ' -f1 "$R/sources.list")" > "$I/src.tar"
head -c 3000000 /dev/urandom > "$I/rand.bin"
: > "$I/empty"
head -c 1000000 /dev/zero > "$I/zeros"
n=0
for f in src.tar rand.bin empty zeros; do
  for lv in 1 5 9; do
    "$G" -c -$lv "$I/$f" > "$I/$f.$lv.g.bz2"; "$Q" -c -$lv "$I/$f" > "$I/$f.$lv.q.bz2"
    cmp -s "$I/$f.$lv.g.bz2" "$I/$f.$lv.q.bz2" || { echo "compress $f -$lv: DIFFERS"; fail=1; }
    "$Q" -dc "$I/$f.$lv.g.bz2" | cmp -s - "$I/$f" || { echo "pxx -d of gcc $f -$lv: DIFFERS"; fail=1; }
    "$G" -dc "$I/$f.$lv.q.bz2" | cmp -s - "$I/$f" || { echo "gcc -d of pxx $f -$lv: DIFFERS"; fail=1; }
    n=$((n + 1))
  done
done
[ "$fail" = 0 ] && echo "compress: $n cases, all identical to gcc's and read back by both"

# 3. -t, concatenated streams, bzip2recover
c=$I/corrupt.bz2
cp "$I/src.tar.9.g.bz2" "$c"
printf 'XXXX' | dd of="$c" bs=1 seek=50000 conv=notrunc 2> /dev/null
for f in "$I/src.tar.9.g.bz2" "$c"; do
  a=$("$G" -t "$f" 2>&1 || echo "rc=$?"); b=$("$Q" -t "$f" 2>&1 || echo "rc=$?")
  same "-t $(basename "$f")" "$(echo "$a" | sed "s|$G|bzip2|g")" "$(echo "$b" | sed "s|$Q|bzip2|g")"
done
cat "$I/src.tar.1.g.bz2" "$I/zeros.5.g.bz2" > "$I/two.bz2"
same "bzcat two streams" "$("$G" -dc "$I/two.bz2" | sha256sum)" "$("$Q" -dc "$I/two.bz2" | sha256sum)"
head -c 400000 "$I/src.tar.1.g.bz2" > "$I/trunc.bz2"
mkdir -p "$I/rg" "$I/rq"
cp "$I/trunc.bz2" "$I/rg/"; cp "$I/trunc.bz2" "$I/rq/"
a=$(cd "$I/rg" && "$REF/bzip2recover" trunc.bz2 2>&1 || echo "rc=$?"; cat rec*trunc.bz2 | sha256sum)
b=$(cd "$I/rq" && "$O/work/bzip2recover" trunc.bz2 2>&1 || echo "rc=$?"; cat rec*trunc.bz2 | sha256sum)
same "bzip2recover" "$(echo "$a" | sed "s|$REF/||")" "$(echo "$b" | sed "s|$O/work/||")"
[ "$fail" = 0 ] && echo "-t, two streams, bzip2recover: identical to gcc's"

# 4. the .tar.bz2 downloads at hand
for f in "$W"/dl/*.tar.bz2 /data/tmp/pathb-st/dl/*.tar.bz2; do
  [ -e "$f" ] || continue
  same "decompress $(basename "$f")" "$("$G" -dc "$f" | sha256sum)" "$("$Q" -dc "$f" | sha256sum)"
  echo "decompress $(basename "$f"): checked"
done
size "$Q" | sed "s|$O/work/||"
if [ "$fail" = 0 ]; then echo "bzip2 recipe: PASS"; else echo "bzip2 recipe: FAIL"; exit 1; fi
