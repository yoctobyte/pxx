#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build sfdisk, fdisk and blkid (util-linux,
# with its own libfdisk, libblkid, libsmartcols, libuuid and libcommon
# linked in) from the recipe with only pxx, a POSIX shell, xz and
# toybox-level tools. No gcc, make or configure: what configure and make
# decided was recorded on the build host (record.sh) and comes in gen.tar
# (the generated sources), `units` and `link`. The tarball is upstream's
# .tar.xz, unpacked with the xz recipe's xzcat.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/util-linux/onsite.sh /tmp/ul [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/sbin/{sfdisk,fdisk,blkid}. Exit status 0 only if every unit
# compiled, every program linked and the smoke test passed.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj" "$WORK/bin"
xzcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# every object some program links, once. util-linux links -lpthread
# (libuuid's clock lock) and keeps libuuid's clock state in __thread
# variables, hence --threadsafe. A failed unit leaves OBJ.fail beside its
# log.
objs=$(cut -d' ' -f2- "$R/link" | tr ' ' '\n' | sort -u)
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with configure's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe -ffile-prefix-map=\"\$WORK/src=/usr/src/util-linux\" $* \"\$src\" \"\$o\"" \
      > "$o.log" 2>&1 || : > "$o.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done
wait
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  exit 1
done
while read -r prog pobjs; do
  list=
  for obj in $pobjs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
  # shellcheck disable=SC2086
  "$PXX" --link -o "$WORK/bin/$prog" $list > "$WORK/link-$prog.log" 2>&1 \
    || { tail -5 "$WORK/link-$prog.log" >&2; exit 1; }
done < "$R/link"

# smoke: partition an image with sfdisk (GPT, two partitions), read the
# table back with sfdisk and fdisk, and have blkid probe it
B=$WORK/bin
img=$WORK/smoke.img
: > "$img"
truncate -s 64M "$img"
printf 'label: gpt\nsize=16M, type=uefi\ntype=linux\n' | "$B/sfdisk" -q "$img" > /dev/null
[ "$("$B/sfdisk" -d "$img" | grep -c '^/')" = 2 ] \
  || { echo "onsite: sfdisk did not write two partitions" >&2; exit 1; }
"$B/fdisk" -l "$img" | grep -q 'Disklabel type: gpt' \
  || { echo "onsite: fdisk does not see the GPT" >&2; exit 1; }
"$B/blkid" -p "$img" | grep -q 'PTTYPE="gpt"' \
  || { echo "onsite: blkid does not see the GPT" >&2; exit 1; }
echo "onsite: $B/sfdisk $B/fdisk $B/blkid"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/sbin"
  for p in sfdisk fdisk blkid; do
    cp "$B/$p" "$DEST/sbin/$p"
    chmod 755 "$DEST/sbin/$p"
  done
  echo "onsite: installed into $DEST"
fi
