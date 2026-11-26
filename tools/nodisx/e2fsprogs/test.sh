#!/bin/sh
# test.sh: PASS/FAIL for the e2fsprogs recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs e2fsprogs' own suite (`make check`, tests/: some 385 scripted
#     cases, most of them e2fsck on a damaged image against its expected
#     output) with the pxx mke2fs, e2fsck and tune2fs in place of gcc's, in a
#     copy of the reference tree; debugfs and the rest stay gcc's;
#  2. makes images with both mke2fs builds over a set of options, with the
#     UUID, hash seed and clock fixed, and compares the images byte for byte
#     and stdout, stderr and the exit status apart.
# PASS is both: no suite failure, every image and output identical to gcc's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/e2fsprogs/test.sh
# Needs record.sh to have run, and make (host only).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/e2fsprogs
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/e2fsprogs-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/e2fsprogs-ref
B=$O/work/bin
fail=0

# 1. the upstream suite, on the pxx programs
mkdir -p "$O/suite"
cp -a "$REF/." "$O/suite/"
for p in e2fsck/e2fsck misc/mke2fs misc/tune2fs; do
  cp "$B/$(basename "$p")" "$O/suite/$p"; touch "$O/suite/$p"
done
( cd "$O/suite" && PXX_ALLOW_FULL_SUITE=1 make -j3 check ) > "$O/check.log" 2>&1 || true
s=$(grep -E 'tests succeeded' "$O/check.log" | tail -1)
echo "e2fsprogs suite: $s"
echo "$s" | grep -qE '^[1-9][0-9]* tests succeeded	0 tests failed$' || fail=1
for p in e2fsck/e2fsck misc/mke2fs misc/tune2fs; do
  cmp -s "$B/$(basename "$p")" "$O/suite/$p" || { echo "test: make rebuilt $p"; fail=1; }
done

# 2. mke2fs images, byte for byte (one -E: a second one replaces the first)
export MKE2FS_CONFIG=$REF/misc/mke2fs.conf E2FSPROGS_FAKE_TIME=1700000000
U=11111111-2222-3333-4444-555555555555
H=hash_seed=66666666-7777-8888-9999-aaaaaaaaaaaa
I=$O/img
mkdir -p "$I"
n=0; same=0
while IFS='|' read -r size eopt opts; do
  n=$((n + 1))
  for b in gcc pxx; do
    if [ $b = gcc ]; then m=$REF/misc/mke2fs; else m=$B/mke2fs; fi
    : > "$I/$b.img"; truncate -s "$size" "$I/$b.img"
    # shellcheck disable=SC2086
    "$m" -F -U $U -E "$H$eopt" $opts "$I/$b.img" > "$I/$b.out" 2> "$I/$b.err" && echo 0 >> "$I/$b.out" || echo $? >> "$I/$b.out"
  done
  if cmp -s "$I/gcc.img" "$I/pxx.img" && cmp -s "$I/gcc.out" "$I/pxx.out" && cmp -s "$I/gcc.err" "$I/pxx.err"; then
    same=$((same + 1))
  else
    echo "mke2fs [$size $eopt $opts]: DIFFERS"; fail=1
  fi
done <<'EOF'
64M||-t ext2
64M||-t ext3
256M||-t ext4
256M||-t ext4 -L nodisx -m 1 -I 256
1G||-t ext4 -O ^has_journal -b 4096
32M||-t ext4 -b 1024 -N 4096
512M|,lazy_itable_init=0|-t ext4 -O metadata_csum,64bit
2G|,lazy_itable_init=0,lazy_journal_init=0|-t ext4 -J size=64
128M||-t ext4 -O inline_data,^resize_inode -i 8192
100M||-t ext4 -T small -g 4096
EOF
echo "mke2fs: $same of $n images and outputs identical to gcc's"
size "$B/mke2fs" "$B/e2fsck" "$B/tune2fs" | sed "s|$B/||"
if [ "$fail" = 0 ]; then echo "e2fsprogs recipe: PASS"; else echo "e2fsprogs recipe: FAIL"; exit 1; fi
