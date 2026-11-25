#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build mksh from its recipe with only pxx, a
# POSIX shell (any: the busybox or toybox one, or a previous mksh) and
# toybox-level tools (zcat, tar, sha256sum). No gcc, make or Build.sh: what
# Build.sh would have decided was recorded on the build host (record.sh) and
# comes in `flags` and gen.tar.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/mksh/onsite.sh /tmp/mksh [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). RECIPE: the recipe directory (default: this
# script's). With DESTDIR, installs DESTDIR/bin/mksh and DESTDIR/bin/sh -> mksh.
# Exit status 0 only if every unit compiled and the shell runs a smoke script.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/build"
zcat "$DL/$name" | tar -xf - -C "$WORK"          # unpacks as mksh/
tar -xf "$R/gen.tar" -C "$WORK/build"
read -r flags < "$R/flags"
objs=
cd "$WORK/build"
while read -r u; do
  o=${u%.c}.o
  # shellcheck disable=SC2086 -- flags are words by design
  "$PXX" --emit-obj --function-sections -ffile-prefix-map="$WORK=/usr/src" -I. -I../mksh $flags "../mksh/$u" "$o" \
    > "$o.log" 2>&1 || { echo "onsite: FAILED $u: $(grep -m1 error "$o.log")" >&2; exit 1; }
  objs="$objs $o"
done < "$R/units"
# shellcheck disable=SC2086
"$PXX" --link -o "$WORK/build/mksh" $objs > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: an external command (fork, exec, wait), a pipe, a here-document,
# command substitution with quotes, arithmetic, a function, a case
out=$("$WORK/build/mksh" -c '
  f() { echo "f:$1"; }
  x=$(echo "a b" | tr a-z A-Z)
  cat <<EOF
$x $((6 * 7)) $(f "q r")
EOF
  case $x in A*) echo case-ok ;; esac
  "$0" -c "exit 3"; echo "rc=$?"
' "$WORK/build/mksh")
want='A B 42 f:q r
case-ok
rc=3'
[ "$out" = "$want" ] || { echo "onsite: mksh smoke test failed:" >&2; echo "$out" >&2; exit 1; }
echo "onsite: $WORK/build/mksh"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/build/mksh" "$DEST/bin/mksh"
  chmod 755 "$DEST/bin/mksh"
  [ -e "$DEST/bin/sh" ] || ln -s mksh "$DEST/bin/sh"
  echo "onsite: installed into $DEST"
fi
