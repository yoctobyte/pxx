#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build bzip2 and bzip2recover from the recipe
# with only pxx, a POSIX shell and toybox-level tools (zcat, tar, sha256sum,
# cmp). No gcc or make: the units and link lines were recorded on the build
# host (record.sh). The tarball is .tar.gz, so toybox's zcat unpacks it.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/bzip2/onsite.sh /tmp/bzip2 [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/bzip2, bzip2recover and the bunzip2 / bzcat links. Exit status
# 0 only if every unit compiled and bzip2 reproduces the source's own three
# reference files (what `make test` checks).
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

# every unit, JOBS at a time; a failed unit leaves OBJ.fail beside its log
i=0
while read -r obj dir src flags; do
  o=$WORK/obj/$obj
  (
    cd "$WORK/src/$dir"
    # shellcheck disable=SC2086 -- the flags are words
    "$PXX" --emit-obj --function-sections --shared-runtime \
      -ffile-prefix-map="$WORK/src=/usr/src/bzip2" $flags "$src" "$o" > "$o.log" 2>&1 || : > "$o.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done < "$R/units"
wait
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  exit 1
done
while read -r prog objs; do
  list=
  for obj in $objs; do list="$list $WORK/obj/$obj"; done
  # shellcheck disable=SC2086
  "$PXX" --link -o "$WORK/$prog" $list > "$WORK/$prog.link.log" 2>&1 || { tail -5 "$WORK/$prog.link.log" >&2; exit 1; }
done < "$R/link"

# smoke: the reference files bzip2 ships, compressed and decompressed
S=$WORK/src
for n in 1 2 3; do
  "$WORK/bzip2" -$n < "$S/sample$n.ref" | cmp -s - "$S/sample$n.bz2" \
    || { echo "onsite: bzip2 -$n does not reproduce sample$n.bz2" >&2; exit 1; }
  "$WORK/bzip2" -d < "$S/sample$n.bz2" | cmp -s - "$S/sample$n.ref" \
    || { echo "onsite: bzip2 -d does not reproduce sample$n.ref" >&2; exit 1; }
done
echo "onsite: $WORK/bzip2 $WORK/bzip2recover"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  for p in bzip2 bzip2recover; do cp "$WORK/$p" "$DEST/bin/$p"; chmod 755 "$DEST/bin/$p"; done
  for l in bunzip2 bzcat; do [ -e "$DEST/bin/$l" ] || ln -s bzip2 "$DEST/bin/$l"; done
  echo "onsite: installed into $DEST"
fi
