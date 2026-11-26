#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build mke2fs, e2fsck and tune2fs (e2fsprogs,
# with its own libext2fs, libcom_err, libe2p, libuuid and libblkid linked
# in) from the recipe with only pxx, a POSIX shell, xz and toybox-level
# tools. No gcc, make or configure: what configure and make decided was
# recorded on the build host (record.sh) and comes in gen.tar (the generated
# sources), `units` and `link`. The tarball is upstream's .tar.xz, unpacked
# with the xz recipe's xzcat.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/e2fsprogs/onsite.sh /tmp/e2fs [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/sbin/{mke2fs,e2fsck,tune2fs} and the mkfs.ext2/3/4, fsck.ext2/3/4
# and e2label links. Exit status 0 only if every unit compiled, every
# program linked and the smoke test passed.
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

# every object some program links, once. e2fsprogs builds with -pthread
# (unix_io's cache lock, libuuid), hence --threadsafe. A failed unit
# leaves OBJ.fail beside its log.
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
    eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe -ffile-prefix-map=\"\$WORK/src=/usr/src/e2fsprogs\" $* \"\$src\" \"\$o\"" \
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

# smoke: make an ext4 image, check it, label it, check it again
B=$WORK/bin
img=$WORK/smoke.img
: > "$img"
truncate -s 32M "$img"
# a config path that does not exist: mke2fs then uses its built-in profile
# (default_profile.c), so the smoke does not depend on the target's /etc
MKE2FS_CONFIG=$WORK/no-mke2fs.conf "$B/mke2fs" -q -F -t ext4 "$img" > /dev/null
"$B/e2fsck" -fn "$img" > "$WORK/smoke.log" 2>&1 || { cat "$WORK/smoke.log" >&2; echo "onsite: e2fsck finds the fresh image damaged" >&2; exit 1; }
"$B/tune2fs" -L nodisx "$img" > /dev/null
[ "$("$B/tune2fs" -l "$img" | sed -n 's/^Filesystem volume name: *//p')" = nodisx ] \
  || { echo "onsite: tune2fs did not set the label" >&2; exit 1; }
"$B/e2fsck" -fn "$img" > /dev/null 2>&1 || { echo "onsite: e2fsck after tune2fs" >&2; exit 1; }
echo "onsite: $B/mke2fs $B/e2fsck $B/tune2fs"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/sbin"
  for p in mke2fs e2fsck tune2fs; do
    cp "$B/$p" "$DEST/sbin/$p"
    chmod 755 "$DEST/sbin/$p"
  done
  for n in 2 3 4; do
    [ -e "$DEST/sbin/mkfs.ext$n" ] || ln -s mke2fs "$DEST/sbin/mkfs.ext$n"
    [ -e "$DEST/sbin/fsck.ext$n" ] || ln -s e2fsck "$DEST/sbin/fsck.ext$n"
  done
  [ -e "$DEST/sbin/e2label" ] || ln -s tune2fs "$DEST/sbin/e2label"
  echo "onsite: installed into $DEST"
fi
