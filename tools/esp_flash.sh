#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Flash a PXX program to a REAL ESP32 board over USB and print what it says.
#
#   tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0]
#                      [--seconds N] [--no-verify] <prog.pas>
#
# The qemu sibling of this script is tools/esp_run.sh, and the two are
# deliberately identical up to the last step: same projects, same compiler
# flags, same output filter. So a program that matches its x86-64 oracle under
# qemu can be re-checked on silicon with one word changed, and --verify (the
# default) does that diff for you: it runs the program natively, captures that
# as the oracle, then compares the board's serial output against it.
#
# Chips. esp32s2 and esp32s3 are Xtensa (windowed ABI), esp32c3 is riscv32.
# There is NO qemu machine for the S2, so the S2 path exists only here — a
# board is the only way to run it.
#
# Prereqs:
#   - ESP-IDF that exports idf.py + toolchains + esptool (default ~/esp/esp-idf,
#     override with ESP_IDF_DIR)
#   - a board on USB, and permission to open its tty (dialout group, usually)
#
# Exit status: 0 when the board ran the program (and, with --verify, when its
# output matched the oracle).
set -uo pipefail

CHIP=esp32s3
PORT=""
SECONDS_TO_READ=10
VERIFY=1
while [ $# -gt 0 ]; do
  case "$1" in
    --chip)       CHIP="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --seconds)    SECONDS_TO_READ="$2"; shift 2 ;;
    --no-verify)  VERIFY=0; shift ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *)            break ;;
  esac
done
PAS="${1:?usage: tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0] <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="$REPO_ROOT/compiler/pascal26"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

case "$CHIP" in
  esp32s2) PROJ="$REPO_ROOT/examples/esp32/hello-s2"
           PXXFLAGS="--target=xtensa --xtensa-abi=windowed --platform=esp" ;;
  esp32s3) PROJ="$REPO_ROOT/examples/esp32/hello-s3"
           PXXFLAGS="--target=xtensa --xtensa-abi=windowed --platform=esp" ;;
  esp32c3) PROJ="$REPO_ROOT/examples/esp32/hello-c3"
           PXXFLAGS="--target=riscv32 --platform=esp" ;;
  *) echo "esp_flash: unknown chip '$CHIP' (esp32s2|esp32s3|esp32c3)" >&2; exit 2 ;;
esac

[ -x "$PXX" ]  || { echo "esp_flash: compiler not built ($PXX) — run make compiler/pascal26" >&2; exit 2; }
[ -d "$PROJ" ] || { echo "esp_flash: IDF project $PROJ missing" >&2; exit 2; }
[ -f "$ESP_IDF_DIR/export.sh" ] || { echo "esp_flash: ESP-IDF not at $ESP_IDF_DIR" >&2; exit 2; }

# Find the board if the caller did not name it. Espressif devkits show up as
# /dev/ttyUSB* (CP210x/CH34x bridge) or /dev/ttyACM* (native USB-serial-JTAG on
# S2/S3/C3). Refuse to guess when several are present — flashing the wrong board
# is not something to be clever about.
if [ -z "$PORT" ]; then
  mapfile -t PORTS < <(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null)
  case "${#PORTS[@]}" in
    0) echo "esp_flash: no /dev/ttyUSB* or /dev/ttyACM* found — is the board plugged in?" >&2; exit 2 ;;
    1) PORT="${PORTS[0]}" ;;
    *) echo "esp_flash: several serial ports (${PORTS[*]}) — pick one with --port" >&2; exit 2 ;;
  esac
fi
[ -w "$PORT" ] || { echo "esp_flash: $PORT is not writable (add yourself to the dialout group and re-login)" >&2; exit 2; }

echo "esp_flash: $CHIP on $PORT <- $(basename "$PAS")" >&2

# The x86-64 oracle, captured BEFORE the board runs: the same source compiled
# natively. A program that talks to hardware only can pass --no-verify.
ORACLE=""
if [ "$VERIFY" = 1 ]; then
  ORACLE="$(mktemp)"
  if "$PXX" "$PAS" /tmp/esp_flash_oracle >/dev/null 2>&1 && /tmp/esp_flash_oracle > "$ORACLE" 2>/dev/null; then
    :
  else
    echo "esp_flash: the program does not build/run on x86-64, so there is no oracle to diff against (continuing with --no-verify)" >&2
    VERIFY=0
    rm -f "$ORACLE"
  fi
fi

# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

cd "$PROJ" || exit 1
# shellcheck disable=SC2086
if ! "$PXX" $PXXFLAGS ${ESP_PXXFLAGS:-} "$PAS" main/main.o >/dev/null; then
  echo "esp_flash: compiling $PAS failed (note: -Fu paths must be absolute)" >&2
  exit 1
fi
ar rcs main/libpxx_app.a main/main.o

# Same relink trick as esp_run.sh: ninja does not see inside the prebuilt
# archive, so drop the image to force one.
if [ -f build/build.ninja ]; then
  rm -f build/*.elf build/*.bin
  ninja -C build >/dev/null || { echo "esp_flash: build failed" >&2; exit 1; }
else
  idf.py set-target "$CHIP" >/dev/null && idf.py build >/dev/null || { echo "esp_flash: build failed" >&2; exit 1; }
fi

cd build || exit 1
echo "esp_flash: writing flash..." >&2
if ! python -m esptool --chip "$CHIP" -p "$PORT" -b 460800 \
     --before default-reset --after hard-reset write-flash "@flash_args" >/dev/null 2>&1; then
  echo "esp_flash: esptool could not write $PORT. Hold BOOT while tapping RESET to force download mode, then retry." >&2
  exit 1
fi

# Read the boot log straight off the tty. `idf.py monitor` is interactive and
# would need a human to quit it; this just reads for N seconds and stops.
# 115200 8N1 is the IDF default console.
stty -F "$PORT" 115200 cs8 -cstopb -parenb -echo raw 2>/dev/null || true
SER="$(mktemp)"
timeout "$SECONDS_TO_READ" cat "$PORT" > "$SER" 2>/dev/null || true

# Everything after "Calling app_main()" is the program's own output; the serial
# console turns each '\n' into '\r\n', so strip the CR to match a Linux oracle.
#
# esptool's hard-reset happens while this script is still getting to the read,
# so on a fast board the banner — and the marker with it — can be gone before
# the tty is open. A missing marker is therefore not an error: fall back to the
# oracle's first line, then to the whole capture, so the user sees what the
# board actually said instead of a bare "nothing arrived".
OUT="$(awk 'f {print} /Calling app_main\(\)/{f=1}' "$SER" | tr -d '\r')"
if [ -z "$OUT" ] && [ -n "$ORACLE" ] && [ -s "$ORACLE" ]; then
  FIRST="$(head -1 "$ORACLE")"
  OUT="$(tr -d '\r' < "$SER" | awk -v k="$FIRST" 'index($0,k){f=1} f {print}')"
  [ -n "$OUT" ] && echo "esp_flash: no boot banner in the capture (the reset raced the reader); synced on the program's first line instead" >&2
fi
if [ -z "$OUT" ]; then
  OUT="$(tr -d '\r' < "$SER")"
  [ -n "$OUT" ] && echo "esp_flash: no 'Calling app_main()' and no oracle match — showing the whole capture" >&2
fi
if [ -z "$OUT" ]; then
  echo "esp_flash: the board said nothing in ${SECONDS_TO_READ}s. Try --seconds 20, or press RESET while it is reading." >&2
  rm -f "$SER" "$ORACLE"
  exit 1
fi
printf '%s\n' "$OUT"
rm -f "$SER"

if [ "$VERIFY" = 1 ]; then
  # The board keeps running (most ESP programs park in a loop), so the capture
  # is a PREFIX of the program's output: compare only as many lines as the
  # oracle has.
  ORACLE_LINES="$(wc -l < "$ORACLE")"
  if printf '%s\n' "$OUT" | head -n "$ORACLE_LINES" | diff -u "$ORACLE" - >/dev/null; then
    echo "esp_flash: OK — board output matches the x86-64 oracle ($ORACLE_LINES lines)" >&2
    rm -f "$ORACLE"
  else
    echo "esp_flash: MISMATCH against the x86-64 oracle:" >&2
    printf '%s\n' "$OUT" | head -n "$ORACLE_LINES" | diff -u "$ORACLE" - >&2
    rm -f "$ORACLE"
    exit 1
  fi
fi
