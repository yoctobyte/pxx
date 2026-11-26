#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build the `limine` host tool with pxx and
# install it with the release's boot loader binaries (record.sh says why
# those are not built here). Only pxx, a POSIX shell and toybox-level tools
# (xzcat, tar, sha256sum, cmp).
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/limine/onsite.sh /tmp/limine [/mnt/target]
#
# DL: the directory holding the tarball in sources.list. PXX: the pxx compiler
# (default `pxx`). RECIPE: the recipe directory (default: this script's).
# With DESTDIR, installs bin/limine; share/limine/ with limine-bios.sys,
# limine-bios-cd.bin, limine-bios-pxe.bin, limine-uefi-cd.bin and the
# BOOT*.EFI images; share/doc/limine/ with LICENSE and 3RDPARTY.md, which
# must accompany the binaries. Exit status 0 only if limine built, reports
# its version, and enroll-config then --reset gives back the shipped
# BOOTX64.EFI byte for byte.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src"
xzcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
S=$WORK/src
"$PXX" -std=c99 -D_FILE_OFFSET_BITS=64 -I"$S" -ffile-prefix-map="$S=/usr/src/limine" \
  "$S/limine.c" "$WORK/limine" > "$WORK/build.log" 2>&1 || { tail -5 "$WORK/build.log" >&2; exit 1; }

# smoke: the version, and an enroll-config round trip on the shipped EFI
v=$("$WORK/limine" --version | head -1)
case $v in "Limine "[0-9]*) ;; *) echo "onsite: limine --version said: $v" >&2; exit 1 ;; esac
cp "$S/BOOTX64.EFI" "$WORK/smoke.efi"
"$WORK/limine" enroll-config "$WORK/smoke.efi" \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  > /dev/null 2>&1 || { echo "onsite: enroll-config failed" >&2; exit 1; }
cmp -s "$WORK/smoke.efi" "$S/BOOTX64.EFI" && { echo "onsite: enroll-config changed nothing" >&2; exit 1; }
"$WORK/limine" enroll-config --reset "$WORK/smoke.efi" > /dev/null 2>&1
cmp -s "$WORK/smoke.efi" "$S/BOOTX64.EFI" || { echo "onsite: enroll-config --reset did not restore the EFI" >&2; exit 1; }
echo "onsite: $WORK/limine ($v)"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin" "$DEST/share/limine" "$DEST/share/doc/limine"
  cp "$WORK/limine" "$DEST/bin/limine"; chmod 755 "$DEST/bin/limine"
  for f in limine-bios.sys limine-bios-cd.bin limine-bios-pxe.bin limine-uefi-cd.bin \
           BOOTX64.EFI BOOTIA32.EFI BOOTAA64.EFI BOOTRISCV64.EFI BOOTLOONGARCH64.EFI; do
    cp "$S/$f" "$DEST/share/limine/$f"; chmod 644 "$DEST/share/limine/$f"
  done
  cp "$S/LICENSE" "$S/3RDPARTY.md" "$DEST/share/doc/limine/"
  echo "onsite: installed into $DEST"
fi
