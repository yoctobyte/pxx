#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build dhcpcd from the recipe with only pxx, a
# POSIX shell and toybox-level tools (xzcat, tar, sha256sum). No gcc, make or
# configure: what configure decided was recorded on the build host
# (record.sh) and comes in gen.tar, `units` and `link`. The tarball is
# .tar.xz, so the xz recipe (and its xzcat) comes first.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/dhcpcd/onsite.sh /tmp/dhcpcd [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# sbin/dhcpcd, libexec/dhcpcd-run-hooks, libexec/dhcpcd-hooks/ (01-test,
# 20-resolv.conf, 30-hostname) and etc/dhcpcd.conf (kept if present), the
# paths configure recorded. Exit status 0 only if every unit compiled, the
# link succeeded and the binary reports its version (a dry run, `-T`, needs
# root and an interface; test.sh compares more).
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
xzcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# compile the objects dhcpcd links, JOBS at a time. The flags keep
# configure's shell quoting (rbtree's -D values hold spaces), hence the eval.
# A failed unit leaves OBJ.fail beside its log.
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
    flags=$(echo "$line" | cut -d' ' -f4-)
    ( eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime -ffile-prefix-map=\"\$WORK/src=/usr/src/dhcpcd\" $flags \"\$src\" \"\$o\"" \
      ) > "$o.log" 2>&1 || : > "$o.fail"
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
"$PXX" --link -o "$WORK/dhcpcd" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: it starts and knows its version
"$WORK/dhcpcd" --version | grep -q '^dhcpcd 10\.' || { echo "onsite: dhcpcd --version failed" >&2; exit 1; }
echo "onsite: $WORK/dhcpcd"

if [ -n "$DEST" ]; then
  S=$WORK/src
  mkdir -p "$DEST/sbin" "$DEST/libexec/dhcpcd-hooks" "$DEST/etc" "$DEST/var/db/dhcpcd"
  cp "$WORK/dhcpcd" "$DEST/sbin/dhcpcd"; chmod 755 "$DEST/sbin/dhcpcd"
  cp "$S/hooks/dhcpcd-run-hooks" "$DEST/libexec/dhcpcd-run-hooks"; chmod 755 "$DEST/libexec/dhcpcd-run-hooks"
  for h in 01-test 20-resolv.conf 30-hostname; do
    cp "$S/hooks/$h" "$DEST/libexec/dhcpcd-hooks/$h"; chmod 644 "$DEST/libexec/dhcpcd-hooks/$h"
  done
  [ -e "$DEST/etc/dhcpcd.conf" ] || { cp "$S/src/dhcpcd.conf" "$DEST/etc/dhcpcd.conf"; chmod 644 "$DEST/etc/dhcpcd.conf"; }
  # privilege separation: the _dhcpcd user and group, and its home, the empty
  # directory the unprivileged processes chroot into. Without the user dhcpcd
  # says "no such user _dhcpcd" and runs every process as root. Added only if
  # absent, with the lowest id in 100..999 that neither file uses.
  mkdir -p "$DEST/var/lib/dhcpcd"; chmod 755 "$DEST/var/lib/dhcpcd"
  touch "$DEST/etc/passwd" "$DEST/etc/group"
  if ! grep -q '^_dhcpcd:' "$DEST/etc/passwd"; then
    id=100
    while cut -d: -f3 "$DEST/etc/passwd" "$DEST/etc/group" | grep -qx "$id"; do id=$((id + 1)); done
    [ "$id" -le 999 ] || { echo "onsite: no free system id for _dhcpcd" >&2; exit 1; }
    grep -q '^_dhcpcd:' "$DEST/etc/group" || echo "_dhcpcd:x:$id:" >> "$DEST/etc/group"
    gid=$(sed -n 's/^_dhcpcd:[^:]*:\([0-9]*\):.*/\1/p' "$DEST/etc/group")
    echo "_dhcpcd:x:$id:$gid:dhcpcd privilege separation:/var/lib/dhcpcd:/bin/false" >> "$DEST/etc/passwd"
    if [ -f "$DEST/etc/shadow" ] && ! grep -q '^_dhcpcd:' "$DEST/etc/shadow"; then
      echo '_dhcpcd:!:1::::::' >> "$DEST/etc/shadow"
    fi
  fi
  echo "onsite: installed into $DEST"
fi
