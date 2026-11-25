#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build toybox from its recipe with only pxx, a
# POSIX shell and toybox-level tools (zcat, tar, sha256sum, cut, mkdir, ln).
# No gcc, make or autoconf: the headers toybox's make.sh would generate with a
# host cc were pre-generated on the build host (record.sh) and come in gen.tar.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/toybox/onsite.sh /tmp/tb [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/toybox and one symlink per applet at the path `toybox --long`
# gives it. Exit status 0 only if every unit compiled and the binary runs.
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

# compile: JOBS at a time; a failed unit leaves OBJ.fail beside its log
i=0
while read -r obj src flags; do
  (
    cd "$WORK/src"
    # shellcheck disable=SC2086 -- flags are words by design
    "$PXX" --emit-obj --function-sections --shared-runtime -ffile-prefix-map="$WORK/src=/usr/src/toybox" $flags "$src" "$WORK/obj/$obj" \
      > "$WORK/obj/$obj.log" 2>&1 || : > "$WORK/obj/$obj.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done < "$R/compile.list"
wait
bad=0
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  o=${f%.fail}
  echo "onsite: FAILED ${o##*/}: $(grep -m1 error "$o.log" || tail -1 "$o.log")" >&2
  bad=$((bad + 1))
done
[ "$bad" = 0 ] || { echo "onsite: $bad units failed" >&2; exit 1; }

# link, in compile.list order
objs=
while read -r obj rest; do objs="$objs $WORK/obj/$obj"; done < "$R/compile.list"
# shellcheck disable=SC2086
"$PXX" --link -o "$WORK/toybox" $objs > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }
"$WORK/toybox" echo "toybox ok" > /dev/null || { echo "onsite: the binary does not run" >&2; exit 1; }
n=$("$WORK/toybox" | wc -w)
echo "onsite: $WORK/toybox ($n applets)"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/toybox" "$DEST/bin/toybox"
  chmod 755 "$DEST/bin/toybox"
  for p in $("$WORK/toybox" --long); do
    case $p in bin/toybox|toybox) continue ;; esac
    mkdir -p "$DEST/$(dirname "$p")"
    [ -e "$DEST/$p" ] || ln -s /bin/toybox "$DEST/$p"
  done
  echo "onsite: installed into $DEST"
fi
