#!/bin/sh
# test.sh: PASS/FAIL for the xz recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs xz-utils' own suite (`make check`) with the pxx xz in place of the
#     gcc one, in a copy of the reference tree: the script tests (test_files,
#     test_compress, test_suffix, ...) drive src/xz/xz;
#  2. decompresses every .tar.xz in sources.lock with both builds and compares;
#  3. compresses a tarball and random data with both builds over a set of
#     options and compares the .xz files byte for byte.
# PASS is all three: no suite failure, and every output identical to gcc's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/xz/test.sh
# Needs record.sh to have run, and make (host only).
set -eu
# the C locale on both sides: crtl has no en_US data, so under LANG=en_US
# pxx's setlocale(LC_ALL, "") stays in C while glibc's groups digits
export LC_ALL=C
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/xz
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/xz-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/xz-ref
G=$REF/src/xz/xz
Q=$O/work/xz
fail=0

# 1. the suite, on the pxx xz
mkdir -p "$O/suite"
cp -a "$REF/." "$O/suite/"
cp "$Q" "$O/suite/src/xz/xz"; touch "$O/suite/src/xz/xz"
( cd "$O/suite" && make -k check ) > "$O/check.log" 2>&1 || true
s=$(grep -E '^# (TOTAL|PASS|SKIP|FAIL|ERROR):' "$O/check.log" | tr '\n' ' ')
echo "xz suite: $s"
grep -q '^# FAIL: *0$' "$O/check.log" && grep -q '^# ERROR: *0$' "$O/check.log" \
  && ! grep -q '^# PASS: *0$' "$O/check.log" || fail=1
cmp -s "$Q" "$O/suite/src/xz/xz" || { echo "test: make rebuilt xz"; fail=1; }

# 2. every .tar.xz the bootstrap pins
"$T/../fetch.sh" > /dev/null
for f in "$W"/dl/*.tar.xz; do
  [ -e "$f" ] || continue
  a=$("$G" -dc "$f" | sha256sum); b=$("$Q" -dc "$f" | sha256sum)
  if [ "$a" = "$b" ]; then echo "decompress $(basename "$f"): same"; else echo "decompress $(basename "$f"): DIFFERS"; fail=1; fi
done

# 3. compression, byte for byte (-T1: single-threaded output is a pure
#    function of the input and the options; -T3 too, given the block size)
I=$O/in
mkdir -p "$I"
zcat "$W/dl/$(cut -d' ' -f1 "$R/sources.list")" > "$I/src.tar"
head -c 2000000 /dev/urandom > "$I/rand.bin"
for f in src.tar rand.bin; do
  for o in "-0 -T1" "-6 -T1" "-9e -T1" "-6 -T3" "--format=lzma -5" "--check=sha256 -3 -T1" "--x86 --lzma2=preset=6 -T1"; do
    # shellcheck disable=SC2086
    a=$("$G" -c $o "$I/$f" | sha256sum); b=$("$Q" -c $o "$I/$f" | sha256sum)
    if [ "$a" = "$b" ]; then :; else echo "compress $f [$o]: DIFFERS"; fail=1; fi
  done
done
[ "$fail" = 0 ] && echo "compress: 14 cases, all identical to gcc's"
size "$Q" | sed "s|$O/work/||"
if [ "$fail" = 0 ]; then echo "xz recipe: PASS"; else echo "xz recipe: FAIL"; exit 1; fi
