#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Flash a PXX program to a REAL ESP32 board over USB and print what it says.
#
#   tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0]
#                      [--seconds N] [--no-verify] [--no-flash] <prog.pas>
#   tools/esp_flash.sh --project examples/esp32/nilpy-hw-c3 [--port ...]
#
# TWO WAYS IN, AND THE SECOND EXISTS BECAUSE THE FIRST CANNOT REACH THE DEMOS
# THAT MATTER MOST ON A BOARD. The bare form above builds <prog.pas> into this
# chip's hello-* project, whose partition table is the IDF stock one: a 1 MB
# factory app. Measured 2026-09-20: the four NilPy demo images are 3,334,208 B
# (nilpy-c3) and 3,335,184 B (nilpy-hw-c3), and their own projects carry a
# custom 0x3C0000 table for exactly that reason. So the NilPy demos were not
# merely awkward to flash this way, they were off by more than 3x -- `--project`
# is how they get to silicon at all.
#
# `--project` DELEGATES THE BUILD to that project's own build.sh and does only
# the part this script uniquely owns: write flash, read the tty, print a
# verdict. That is deliberate. The project holds the authoritative compiler
# flags (nilpy-s3 needs --xtensa-long-calls, which a 3.3 MB image cannot link
# without), its own partition table and its own relink trick, and a second copy
# of any of that here would be a spelling that drifts. One owner for the build,
# one for the board.
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

CHIP=""
PORT=""
SECONDS_TO_READ=10
VERIFY=1
PROJECT=""
NO_FLASH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --chip)       CHIP="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --seconds)    SECONDS_TO_READ="$2"; shift 2 ;;
    --no-verify)  VERIFY=0; shift ;;
    --project)    PROJECT="$2"; shift 2 ;;
    --no-flash)   NO_FLASH=1; shift ;;
    -h|--help)    sed -n '2,45p' "$0"; exit 0 ;;
    *)            break ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -n "$PROJECT" ]; then
  PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || {
    echo "esp_flash: --project directory not found" >&2; exit 2; }
  [ -x "$PROJECT/build.sh" ] || {
    echo "esp_flash: $PROJECT has no executable build.sh -- --project drives a project's own build" >&2; exit 2; }
  # The chip comes from the directory SUFFIX, the same rule the demo projects
  # already use to pick their target, so the two cannot disagree. --chip still
  # wins if given.
  if [ -z "$CHIP" ]; then
    case "$(basename "$PROJECT")" in
      *-c3) CHIP=esp32c3 ;;
      *-s3) CHIP=esp32s3 ;;
      *-s2) CHIP=esp32s2 ;;
      *) echo "esp_flash: cannot infer the chip from '$(basename "$PROJECT")' -- pass --chip" >&2; exit 2 ;;
    esac
  fi
  PAS=""
else
  [ -n "$CHIP" ] || CHIP=esp32s3
  PAS="${1:?usage: tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0] <prog.pas>   (or: --project <idf-project-dir>)}"
  PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"
fi

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
# --project overrides the chip's default project AFTER the case, so an unknown
# chip is still refused above rather than silently accepted.
[ -n "$PROJECT" ] && PROJ="$PROJECT"

# The compiler is only this script's business on the bare form. Under
# --project the project's build.sh chooses it -- by default the PIN, which is
# what the demo IS; export PXX to point it elsewhere.
if [ -z "$PROJECT" ]; then
  [ -x "$PXX" ] || { echo "esp_flash: compiler not built ($PXX) — run make compiler/pascal26" >&2; exit 2; }
fi
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

echo "esp_flash: $CHIP on $PORT <- ${PAS:+$(basename "$PAS")}${PROJECT:+$(basename "$PROJECT") (its own build.sh)}" >&2

# The x86-64 oracle, captured BEFORE the board runs: the same source compiled
# natively. A program that talks to hardware only can pass --no-verify.
#
# UNDER --project THE ORACLE IS THE PROJECT'S OWN main/main.expected, and the
# claim it supports is WEAKER FOR SOME PROJECTS THAN OTHERS -- say which,
# because "OK" reads the same either way. For nilpy-c3/nilpy-s3 that file is
# CPython's output for the same program, so a pass there is a real differential
# against CPython. For nilpy-hw-* the program imports pxx Pascal units CPython
# has no equivalent of, so the file is the program's SPECIFICATION: a pass
# witnesses that the SDK timer callback fired and the Python loop saw it, which
# is worth having and is not an oracle claim.
ORACLE=""
if [ "$VERIFY" = 1 ] && [ -n "$PROJECT" ]; then
  if [ -f "$PROJ/main/main.expected" ]; then
    ORACLE="$(mktemp)"
    cat "$PROJ/main/main.expected" > "$ORACLE"
  else
    echo "esp_flash: $PROJ has no main/main.expected, so there is nothing to diff against (continuing with --no-verify)" >&2
    VERIFY=0
  fi
elif [ "$VERIFY" = 1 ]; then
  ORACLE="$(mktemp)"
  ORACLE_BIN="$(mktemp)"   # was the fixed /tmp/esp_flash_oracle, shared by every checkout
  if "$PXX" "$PAS" "$ORACLE_BIN" >/dev/null 2>&1 && "$ORACLE_BIN" > "$ORACLE" 2>/dev/null; then
    :
  else
    echo "esp_flash: the program does not build/run on x86-64, so there is no oracle to diff against (continuing with --no-verify)" >&2
    VERIFY=0
    rm -f "$ORACLE"
  fi
  rm -f "$ORACLE_BIN" "$ORACLE_BIN.map"
fi

# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

# ONE BUILD PER PROJECT AT A TIME: this shares $PROJ (main/main.o, build/)
# with tools/esp_run.sh, and a concurrent run there swaps the program under
# the image this writes to the board. Same lock, on the project directory,
# held to exit -- see esp_run.sh for the measurement.
exec 9<"$PROJ"
flock 9

cd "$PROJ" || exit 1

if [ -n "$PROJECT" ]; then
  # DELEGATED: the project's build.sh owns the flags, the partition table and
  # the relink. Called with no verb, which is its build-only form -- NOT
  # qemu-assert, because booting under qemu here would be a second run of a
  # thing that has its own gate, and would report a verdict about qemu in a
  # tool whose entire purpose is to report one about silicon.
  echo "esp_flash: building via $PROJ/build.sh ..." >&2
  if ! ./build.sh >&2; then
    echo "esp_flash: $PROJ/build.sh failed -- nothing was written to the board" >&2
    exit 1
  fi
else
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
fi

cd build || exit 1
# --no-flash: read and judge what the board is ALREADY running, without
# rewriting it. The question it answers is the one a board raises and qemu does
# not -- "is it still producing the right output, or did it stop" -- and the
# answer is the same verdict, so it is the same code path minus one step. A
# program that parks in a loop re-prints; one that hung does not, and a capture
# that comes back short is exactly what a hang looks like from outside.
if [ "$NO_FLASH" = 1 ]; then
  echo "esp_flash: --no-flash -- reading $PORT without rewriting the board" >&2
else
  echo "esp_flash: writing flash..." >&2
  if ! python -m esptool --chip "$CHIP" -p "$PORT" -b 460800 \
       --before default-reset --after hard-reset write-flash "@flash_args" >/dev/null 2>&1; then
    echo "esp_flash: esptool could not write $PORT. Hold BOOT while tapping RESET to force download mode, then retry." >&2
    exit 1
  fi
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
# Under --project, drop IDF's own log lines too, because the expected file was
# written against a capture that had them dropped (build.sh qemu-assert uses
# the same filter). Scoped to --project ON PURPOSE: widening the bare form's
# filter would change what a hello-* run compares, and that path is the tested
# one.
# THE STRIP BELOW REMOVES IDF'S *ERROR* LINES TOO, SO SCAN FOR THEM FIRST.
# Measured 2026-09-24 on a synthetic capture: a run containing
#   E (5123) task_wdt: Task watchdog got triggered...
#   W (5123) heap_init: corrupt heap detected at 0x3fca1234
# came out of this filter as a clean, contiguous tick=1..3 and the script below
# printed "OK -- board output matches". Those two lines are not incidental: a
# watchdog trigger is what a hung ISR looks like, and a corrupt-heap report is
# how an allocation inside an interrupt handler surfaces -- which is exactly the
# contract the second acceptance row of feature-esp-hardware-flash-validation
# exists to check. The instrument built to catch that was deleting its evidence.
#
# Scanned BEFORE the strip, and outside the --project and --verify conditions on
# purpose: that ticket's ISR step runs with --no-verify, so it performs no
# comparison at all and an error line is otherwise never reported by anything.
#
# E FAILS, W ONLY REPORTS, and the asymmetry is about which target was measured.
# Zero E and zero W lines in a real boot of examples/esp32/nilpy-c3's image under
# Espressif qemu (esp32c3; 59 lines, 46 I-lines, app_main reached -- so logging
# was demonstrably live at a level that would have shown them), which is why E
# can fail without being born red. That measurement is QEMU, and the target that
# matters here is SILICON: a physical part's bootloader may warn routinely where
# qemu does not, so W stays advisory until someone says which board and which
# chip emitted one.
ESP_ERR_LINES="$(printf '%s\n' "$OUT" | grep -E '^E \([0-9]+\) ' || true)"
ESP_WARN_LINES="$(printf '%s\n' "$OUT" | grep -E '^W \([0-9]+\) ' || true)"

if [ -n "$PROJECT" ] && [ -n "$OUT" ]; then
  OUT="$(printf '%s\n' "$OUT" | awk '!/^[IWE] \([0-9]+\) /')"
fi
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

# A REBOOT IS A FAILURE THE COMPARISON CANNOT SEE, because a panic loop reprints
# the program's first lines and a prefix diff matches them happily.
# examples/esp32/nilpy-c3/build.sh qemu-assert already asserts boots == 1; this
# script asserted nothing -- the same guard, present in one of the two places
# that need it. The bound here is >= 2 rather than == 1 because esptool's hard
# reset races the reader, so a capture with NO banner is ordinary and expected
# (the fallbacks above say so).
ESP_BOOTS="$(grep -c 'ESP-ROM' "$SER" || true)"
rm -f "$SER"

if [ -n "$ESP_WARN_LINES" ]; then
  echo "esp_flash: the board logged IDF WARNINGS (not a failure -- if you report one, say which chip and whether it was silicon or qemu):" >&2
  printf '%s\n' "$ESP_WARN_LINES" | sed 's/^/    /' >&2
fi

if [ -n "$ESP_ERR_LINES" ]; then
  echo "esp_flash: FAIL -- the board logged IDF ERRORS. They are stripped before the output comparison, so without this check the run reports OK:" >&2
  printf '%s\n' "$ESP_ERR_LINES" | sed 's/^/    /' >&2
  exit 1
fi

if [ "${ESP_BOOTS:-0}" -ge 2 ]; then
  echo "esp_flash: FAIL -- the board rebooted during the capture (${ESP_BOOTS} boot banners). A panic loop reprints the program's first lines, which a prefix comparison matches." >&2
  exit 1
fi

if [ "$VERIFY" = 1 ]; then
  # The board keeps running (most ESP programs park in a loop), so the capture
  # is a PREFIX of the program's output: compare only as many lines as the
  # oracle has.
  ORACLE_LINES="$(wc -l < "$ORACLE")"
  # NAME THE ORACLE THE VERDICT WAS TAKEN AGAINST, because "OK" reads the same
  # whichever it was and the two support different claims -- a native run is a
  # differential, a checked-in .expected is whatever that file is. A verdict
  # that does not say what it compared against gets quoted as the stronger one.
  if [ -n "$PROJECT" ]; then WHAT="$(basename "$PROJ")/main/main.expected"
  else WHAT="the x86-64 oracle"; fi
  if printf '%s\n' "$OUT" | head -n "$ORACLE_LINES" | diff -u "$ORACLE" - >/dev/null; then
    echo "esp_flash: OK — board output matches $WHAT ($ORACLE_LINES lines)" >&2
    rm -f "$ORACLE"
  else
    echo "esp_flash: MISMATCH against $WHAT (a SHORT capture is what a hang looks like -- check the diff for where it stopped):" >&2
    printf '%s\n' "$OUT" | head -n "$ORACLE_LINES" | diff -u "$ORACLE" - >&2
    rm -f "$ORACLE"
    exit 1
  fi
fi
