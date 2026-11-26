#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build zstd from the recipe with only pxx, a
# POSIX shell and toybox-level tools (zcat, tar, sha256sum, cmp). No gcc or
# make: the units and the link line were recorded on the build host
# (record.sh). The tarball is .tar.gz, so toybox's zcat unpacks it.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/zstd/onsite.sh /tmp/zstd [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/zstd and the unzstd / zstdcat links. Exit status 0 only if
# every unit compiled and zstd round-trips a smoke file, also with -T2.
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

# compile the objects zstd links, JOBS at a time. Its compression workers are
# pthreads, hence --threadsafe. A failed unit leaves OBJ.fail beside its log.
read -r prog objs < "$R/link"
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    "$PXX" --emit-obj --function-sections --shared-runtime --threadsafe \
      -ffile-prefix-map="$WORK/src=/usr/src/zstd" "$@" "$src" "$o" > "$o.log" 2>&1 || : > "$o.fail"
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
"$PXX" --link -o "$WORK/zstd" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: compress and decompress through a pipe, single- and multi-threaded
"$WORK/zstd" --version > /dev/null
i=0
while [ $i -lt 2000 ]; do printf 'nodisx smoke %s\n' $i; i=$((i + 1)); done > "$WORK/smoke.txt"
for t in 1 2; do
  "$WORK/zstd" -q -c -T$t -19 "$WORK/smoke.txt" | "$WORK/zstd" -q -dc | cmp -s - "$WORK/smoke.txt" \
    || { echo "onsite: zstd -T$t does not round-trip a smoke file" >&2; exit 1; }
done
echo "onsite: $WORK/zstd"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/zstd" "$DEST/bin/zstd"
  chmod 755 "$DEST/bin/zstd"
  for l in unzstd zstdcat; do [ -e "$DEST/bin/$l" ] || ln -s zstd "$DEST/bin/$l"; done
  echo "onsite: installed into $DEST"
fi
