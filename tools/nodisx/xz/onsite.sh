#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build xz (xz-utils, with liblzma linked in)
# from the recipe with only pxx, a POSIX shell and toybox-level tools (zcat,
# tar, sha256sum). No gcc, make, libtool or configure: what configure decided
# was recorded on the build host (record.sh) and comes in gen.tar (config.h),
# `units` and `link`. The tarball is .tar.gz, so toybox's zcat unpacks it;
# every later .tar.xz in the bootstrap needs the xzcat this installs.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/xz/onsite.sh /tmp/xz [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/xz and the unxz / xzcat links. Exit status 0 only if every unit
# compiled and xz round-trips a smoke file.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj"
zcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# compile the objects xz links, JOBS at a time. liblzma's worker threads are
# pthreads, hence --threadsafe. A failed unit leaves OBJ.fail beside its log.
read -r prog objs < "$R/link"
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with configure's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe -ffile-prefix-map=\"\$WORK/src=/usr/src/xz\" $* \"\$src\" \"\$o\"" \
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
list=
for obj in $objs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
# shellcheck disable=SC2086
"$PXX" --link -o "$WORK/xz" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: compress and decompress, through a pipe and with the xzcat name
"$WORK/xz" --version > /dev/null
printf 'nodisx smoke %s\n' 1 2 3 4 5 6 7 8 9 > "$WORK/smoke.txt"
"$WORK/xz" -c -6 "$WORK/smoke.txt" | "$WORK/xz" -dc | cmp -s - "$WORK/smoke.txt" \
  || { echo "onsite: xz does not round-trip a smoke file" >&2; exit 1; }
echo "onsite: $WORK/xz"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/xz" "$DEST/bin/xz"
  chmod 755 "$DEST/bin/xz"
  for l in unxz xzcat; do [ -e "$DEST/bin/$l" ] || ln -s xz "$DEST/bin/$l"; done
  echo "onsite: installed into $DEST"
fi
