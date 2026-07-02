#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Provision minimal aarch64 / arm32 (armel) guest runtimes (ld.so + libc) so
# QEMU user-mode can run *dynamically linked* PXX binaries — needed only by the
# external-C-call tests (test_*_extern). Static PXX binaries need no sysroot.
#
# Non-invasive: downloads the Ubuntu libc6-*-cross .debs and extracts them into
# ~/.cache/pxx-cross/<arch> (no system install, no binfmt). tools/run_target.sh
# auto-sets QEMU_LD_PREFIX to these dirs when present.
#
# Needs: apt-get (download only, no sudo), dpkg-deb.
set -eu

dest="${PXX_CROSS_SYSROOT:-$HOME/.cache/pxx-cross}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# arch  deb-package                 lib-subdir-in-deb            sonames-glob
provision() {
  arch="$1"; pkg="$2"; libdir="$3"
  echo "==> $arch ($pkg)"
  ( cd "$tmp" && apt-get download "$pkg" )
  deb="$(ls "$tmp/$pkg"*.deb)"
  rm -rf "$tmp/x_$arch"; mkdir -p "$tmp/x_$arch"
  dpkg-deb -x "$deb" "$tmp/x_$arch"
  rm -rf "$dest/$arch"; mkdir -p "$dest/$arch/lib"
  cp -a "$tmp/x_$arch/$libdir/." "$dest/$arch/lib/"
  echo "    -> $dest/$arch/lib"
}

provision aarch64 libc6-arm64-cross usr/aarch64-linux-gnu/lib
provision arm32   libc6-armel-cross usr/arm-linux-gnueabi/lib

echo
echo "provisioned cross sysroots under $dest"
ls "$dest"/aarch64/lib/ld-linux-aarch64.so.1 "$dest"/arm32/lib/ld-linux.so.3
