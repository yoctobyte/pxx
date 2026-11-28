#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build mkfs.fat, fsck.fat and fatlabel
# (dosfstools) from the recipe with only pxx, a POSIX shell and toybox-level
# tools (zcat, tar, sha256sum). No gcc, make or configure: what configure
# decided was recorded on the build host (record.sh) and comes in `flags` and
# gen.tar.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/dosfstools/onsite.sh /tmp/dosfs [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). RECIPE: the recipe directory (default: this
# script's). With DESTDIR, installs DESTDIR/sbin/{mkfs.fat,fsck.fat,fatlabel}
# and the mkfs.vfat / fsck.vfat links. Exit status 0 only if every unit
# compiled and mkfs.fat formats an image that fsck.fat accepts.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj" "$WORK/bin"
zcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"
read -r flags < "$R/flags"
cd "$WORK/src/src"
# a unit shared by two programs (common.c, charconv.c) compiles once: the
# flags are the same for every unit
while read -r prog units; do
  objs=
  for u in $units; do
    o=$WORK/obj/$(echo "$u" | tr / _ | sed 's/\.c$/.o/')
    if [ ! -f "$o" ]; then
      # shellcheck disable=SC2086 -- flags are words by design (configure's DEFS, quoted for sh)
      ( eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime -ffile-prefix-map=\"\$WORK/src=/usr/src/dosfstools\" $flags -I. -I./blkdev \"\$u\" \"\$o\"" \
        ) > "$o.log" 2>&1 || { echo "onsite: FAILED $u: $(grep -m1 error "$o.log")" >&2; exit 1; }
    fi
    objs="$objs $o"
  done
  # shellcheck disable=SC2086
  "$PXX" --link -o "$WORK/bin/$prog" $objs > "$WORK/link-$prog.log" 2>&1 || { tail -5 "$WORK/link-$prog.log" >&2; exit 1; }
done < "$R/units"

# smoke: format a 2 MB image as FAT12 with a label, check it, read the label
img=$WORK/smoke-$$.img    # -C creates it, and refuses one that exists
"$WORK/bin/mkfs.fat" -C -n NODISX "$img" 2048 > "$WORK/smoke.log" 2>&1
"$WORK/bin/fsck.fat" -n "$img" >> "$WORK/smoke.log" 2>&1 || true
"$WORK/bin/fsck.fat" -n "$img" > /dev/null 2>&1 \
  || { echo "onsite: fsck.fat rejects the image mkfs.fat made:" >&2; cat "$WORK/smoke.log" >&2; exit 1; }
label=$("$WORK/bin/fatlabel" "$img" 2>/dev/null)
[ "$label" = NODISX ] || { echo "onsite: fatlabel read '$label', not NODISX" >&2; exit 1; }
echo "onsite: $WORK/bin: mkfs.fat fsck.fat fatlabel"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/sbin"
  for p in mkfs.fat fsck.fat fatlabel; do
    cp "$WORK/bin/$p" "$DEST/sbin/$p"
    chmod 755 "$DEST/sbin/$p"
  done
  [ -e "$DEST/sbin/mkfs.vfat" ] || ln -s mkfs.fat "$DEST/sbin/mkfs.vfat"
  [ -e "$DEST/sbin/fsck.vfat" ] || ln -s fsck.fat "$DEST/sbin/fsck.vfat"
  echo "onsite: installed into $DEST"
fi
