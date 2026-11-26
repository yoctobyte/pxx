#!/bin/sh
# test.sh: build the limine tool with onsite.sh (pxx) and with gcc from the
# same limine.c, and compare what they do:
#   1. --version, --help, --print-datadir, an unknown command, and the two
#      commands with no arguments (their usage)
#   2. bios-install on a 64 MiB MBR image and on a GPT image with a BIOS boot
#      partition: the images must be byte-identical, as must the messages,
#      and the install must have changed the image
#   3. bios-install on an image with no partition table and on a GPT image
#      without a BIOS boot partition: both refuse, identically, and undo
#   4. enroll-config with a BLAKE2B hash on BOOTX64.EFI and BOOTAA64.EFI:
#      identical files; --reset gives back the shipped file byte for byte
# Host: needs gcc, sfdisk and truncate. The boot loaders are the release's
# binaries; booting an installed image is left to the Path B QEMU image.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/limine/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
R=$W/recipe/limine
[ -f "$R/sources.list" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" limine-test.XXXXXX)
DL=$W/dl PXX=$PXX RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
S=$O/work/src
gcc -O2 -std=c99 -D_FILE_OFFSET_BITS=64 -I"$S" "$S/limine.c" -o "$O/limine-gcc"
G=$O/limine-gcc
P=$O/root/bin/limine
fail=0

# compare NAME CMD... : run CMD with $L set to the gcc build, then to the pxx
# one, in a fresh copy of the work files; output and exit status must match
compare() {
  name=$1; shift
  g=$(L=$G; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  p=$(L=$P; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  g=$(printf '%s\n' "$g" | sed "s|$G|PROG|g")
  p=$(printf '%s\n' "$p" | sed "s|$P|PROG|g")
  if [ "$g" = "$p" ]; then
    echo "same    $name ($(printf '%s\n' "$g" | tail -1))"
  else
    echo "DIFFERS $name"
    printf '%s\n' "$g" > "$O/$name.gcc"; printf '%s\n' "$p" > "$O/$name.pxx"
    diff "$O/$name.gcc" "$O/$name.pxx" | head -10
    fail=1
  fi
}

# --- 1. the command line ---
compare version '"$L" --version'
compare help '"$L" --help'
compare datadir '"$L" --print-datadir'
compare unknown '"$L" no-such-command'
compare bios-install-usage '"$L" bios-install'
compare enroll-usage '"$L" enroll-config'

# --- 2 and 3. bios-install ---
D=$O/img
mkdir -p "$D"
mk() {   # mk NAME SFDISK-SCRIPT (empty: no partition table)
  truncate -s 64M "$D/$1.img"
  [ -z "$2" ] || printf "$2" | sfdisk -q "$D/$1.img"
}
mk mbr 'label: dos\nstart=2048, type=83\n'
mk gpt 'label: gpt\nstart=2048, size=2048, type=21686148-6449-6E6F-744E-656564454649\nstart=4096, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n'
mk gpt-nobios 'label: gpt\nstart=2048, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n'
mk raw ''
for img in mbr gpt gpt-nobios raw; do
  for c in gcc pxx; do cp "$D/$img.img" "$D/$img-$c.img"; done
  compare "bios-install-$img" '"$L" bios-install "$D/'$img'-$( [ "$L" = "$G" ] && echo gcc || echo pxx).img"'
  if cmp -s "$D/$img-gcc.img" "$D/$img-pxx.img"; then echo "same    bios-install-$img image"
  else echo "DIFFERS bios-install-$img image"; fail=1; fi
  case $img in
    mbr|gpt) cmp -s "$D/$img.img" "$D/$img-pxx.img" && { echo "WRONG   bios-install-$img changed nothing"; fail=1; } ;;
    *) cmp -s "$D/$img.img" "$D/$img-pxx.img" || { echo "WRONG   bios-install-$img did not undo"; fail=1; } ;;
  esac
done

# --- 4. enroll-config ---
H=$(printf '%s' 'nodisx limine test' | sha256sum | cut -c1-64)$(printf '%s' 'second half' | sha256sum | cut -c1-64)
for e in BOOTX64.EFI BOOTAA64.EFI; do
  for c in gcc pxx; do cp "$S/$e" "$O/$e-$c"; done
  compare "enroll-$e" '"$L" enroll-config "$O/'$e'-$( [ "$L" = "$G" ] && echo gcc || echo pxx)" '$H
  if cmp -s "$O/$e-gcc" "$O/$e-pxx" && ! cmp -s "$O/$e-pxx" "$S/$e"; then echo "same    enroll-$e file"
  else echo "DIFFERS enroll-$e file (or unchanged)"; fail=1; fi
  compare "enroll-reset-$e" '"$L" enroll-config --reset "$O/'$e'-$( [ "$L" = "$G" ] && echo gcc || echo pxx)"'
  cmp -s "$O/$e-pxx" "$S/$e" || { echo "WRONG   enroll --reset did not restore $e"; fail=1; }
done

size "$P" 2> /dev/null || :
if [ $fail = 0 ]; then echo "limine recipe: PASS"; else echo "limine recipe: FAIL (see $O)"; exit 1; fi
