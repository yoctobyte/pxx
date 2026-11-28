#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build pixix's busybox (394 applets) from the
# recipe with only pxx, a POSIX shell and toybox-level tools (bzcat, tar,
# sha256sum). No gcc, make or kconfig: what the configuration and the
# host-compiled generators decided was recorded on the build host
# (record.sh) and comes in gen.tar, `units` and `link`.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/busybox/onsite.sh /tmp/busybox [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/busybox. Exit status 0 only if every unit compiled, it linked,
# and the new busybox lists its applets and runs a smoke script in its ash.
# busybox is GPL-2.0; its source is on the ISO beside this recipe.
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
bzcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

read -r prog objs < "$R/link"
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with Kbuild's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    ( eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime -ffile-prefix-map=\"\$WORK/src=/usr/src/busybox\" $* \"\$src\" \"\$o\"" \
      ) > "$o.log" 2>&1 || : > "$o.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done
wait
n=0
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  n=$((n + 1))
done
[ "$n" = 0 ] || exit 1
list=
for obj in $objs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
# shellcheck disable=SC2086
"$PXX" --link -o "$WORK/$prog" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: the applets are there, and a script runs through its own ash
n=$("$WORK/busybox" --list | wc -l)
[ "$n" -ge 390 ] || { echo "onsite: busybox lists $n applets" >&2; exit 1; }
got=$("$WORK/busybox" sh -c 'x=$((6 * 7)); for w in b a; do echo $w; done | "$0" sort | "$0" tr "\n" " "; echo $x' "$WORK/busybox")
[ "$got" = "a b 42" ] || { echo "onsite: smoke script printed '$got'" >&2; exit 1; }
echo "onsite: $WORK/busybox ($n applets)"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/busybox" "$DEST/bin/busybox"
  chmod 755 "$DEST/bin/busybox"
  echo "onsite: installed into $DEST"
fi
