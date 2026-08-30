#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3) lwIP RESOLVER smoke (feature-dns-esp-backend):
# compile main.pas with -dPXX_DNS_LIBC so dns_libc binds lwip_getaddrinfo
# directly, wrap it in an archive, drive the normal IDF build, and (optionally)
# boot headless under Espressif QEMU and assert the smoke prints status=0.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
#          ./build.sh qemu       build, then boot headless under QEMU + assert
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"

# Track B builds against the pinned stable compiler, not the in-flux one.
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"
[ -x "$PXX" ] || PXX="$REPO_ROOT/compiler/pascal26"

# --platform=esp and --no-signals are BOTH required, and each is silent when
# missing:
#   --platform=esp   auto-defines PXX_ESP_IDF, which backs PXXAlloc with the
#                    IDF heap (calloc/free externals). Without it the heap
#                    takes the hosted-linux branch and mmap is an ecall.
#   --no-signals     omits the SIGINT/SIGTERM runtime, whose install is an
#                    rt_sigaction ecall in app_main's prologue.
# An ecall under FreeRTOS is an unhandled M-mode trap: the app panics at
# "Calling app_main()" and boot-loops. Neither flag alone is enough.
# -dPXX_DNS_LIBC selects the getaddrinfo backend. Note NO -dPXX_DYNLIB_LIBC:
# on ESP the symbol is a direct external statically linked by idf.py, so the
# runtime loader is neither needed nor available, and dns.pas exempts ESP from
# the guard that normally requires it.
"$PXX" --target=riscv32 --platform=esp --no-signals -dPXX_DNS_LIBC \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32c3
idf.py build

grep -q " app_main" build/pxx_dns_c3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)"
  [ -n "$QEMU" ] || { echo "qemu-system-riscv32 not found under ~/.espressif" >&2; exit 2; }
  ( cd build && python -m esptool --chip esp32c3 merge-bin -o /tmp/pxx_dns_c3_flash.bin @flash_args --fill-flash-size 2MB )
  # Boot, capture serial, kill once the smoke line appears (app parks forever).
  out="$(timeout "${QEMU_TIMEOUT:-25}" "$QEMU" \
      -M esp32c3 -drive file=/tmp/pxx_dns_c3_flash.bin,if=mtd,format=raw \
      -nographic -serial mon:stdio -monitor none 2>/dev/null || true)"
  echo "$out" | grep -a 'PXX-dns-smoke' || true
  if echo "$out" | grep -qa 'PXX-dns-smoke status=0'; then
    echo "esp32c3 lwIP resolver smoke: PASS"
  else
    echo "esp32c3 lwIP resolver smoke: FAIL" >&2
    exit 1
  fi
fi
