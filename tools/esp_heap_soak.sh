#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Heap soak of an examples/esp32 Pascal program under the Espressif QEMU.
#
#   tools/esp_heap_soak.sh [--control] [--passes N] <example-dir-name>
#
# The example is staged OUT OF TREE (the checkout stays byte-clean). Its main
# program body becomes `procedure SoakBody`, and a new main runs it twice to
# warm up, reads IDF's free heap (esp_get_free_heap_size, declared directly so
# no example needs espsys on its -Fu path; it sees pxx's own allocations: on
# the IDF profile PXXAlloc IS newlib malloc), runs it N more times and reads the heap again. It prints
#   SOAK <example> <chip> delta=<bytes> passes=<N> bpp=<bytes per pass>
# and, last, SOAK-COMPLETE. Grep for that token; the wrapper's exit status is
# not the verdict.
#
# Every vTaskDelay(..) becomes vTaskDelay(1): it counts ticks, and the
# examples' blink/poll waits would otherwise take most of a minute per pass.
# The body's `while True do` loops are rewritten: an idle loop on one line
# (`while True do vTaskDelay(1000);`) is removed, and a loop with a block body
# runs SOAK_INNER times (default 2), so a blink/poll example still does its
# work once or twice per pass.
#
# --control adds a deliberate `GetMem(p, 64)` with no free to every pass: the
# instrument must then read 64 + the allocator's per-block header (12 on both
# chips, measured 2026-09-25) per pass. That is the positive control at the same
# scale and in the same program as the measurement.
#
# SOAK_SRC=<dir> soaks <dir>/<example> instead: a unit-level variant (set up
# once behind a guard, exercise one RTL surface per pass) staged the same way.
#
# Built with THIS checkout's compiler/pascal26 (SOAK_PXX overrides), using the
# example's own build.sh flags and sdkconfig.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL=0; PASSES="${SOAK_N:-10}"
while [ $# -gt 0 ]; do
  case "$1" in
    --control) CONTROL=1; shift ;;
    --passes) PASSES="$2"; shift 2 ;;
    *) break ;;
  esac
done
EX="${1:?usage: esp_heap_soak.sh [--control] [--passes N] <example>}"
SRC="${SOAK_SRC:-$REPO_ROOT/examples/esp32}/$EX"   # SOAK_SRC: a dir of example-shaped variants
[ -f "$SRC/main/main.pas" ] || { echo "soak: $EX has no main/main.pas" >&2; exit 2; }
PXX="${SOAK_PXX:-$REPO_ROOT/compiler/pascal26}"
TIMEOUT="${SOAK_TIMEOUT:-180}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

W="$(mktemp -d "${TMPDIR:-/tmp}/esp-soak.XXXXXX")"
QPID=""
cleanup() {
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  if [ -n "${SOAK_KEEP:-}" ]; then echo "soak: stage kept at $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT

mkdir -p "$W/$EX"
tar -C "$SRC" --exclude=build --exclude=sdkconfig --exclude='*.o' --exclude='*.a' -cf - . \
  | tar -C "$W/$EX" -xf -
cd "$W/$EX"

# `set-target` often sits inside a conditional; the dir suffix is the fallback
CHIP="$(grep -o 'set-target esp32[a-z0-9]*' build.sh | head -1 | sed 's/set-target //' || true)"
if [ -z "$CHIP" ]; then
  case "$EX" in *-c3) CHIP=esp32c3 ;; *-s3) CHIP=esp32s3 ;; *-s2) CHIP=esp32s2 ;; esac
fi
[ -n "$CHIP" ] || { echo "soak: no set-target in $EX/build.sh" >&2; exit 2; }

python3 - "$PASSES" "${SOAK_INNER:-2}" "$CONTROL" main/main.pas <<'PY'
import re, sys
passes, inner, control, path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == '1', sys.argv[4]
L = open(path).read().split('\n')
b = max(i for i, l in enumerate(L) if re.match(r'^begin\s*$', l))
e = max(i for i, l in enumerate(L) if re.match(r'^end\.\s*$', l))
body = []
for l in L[b + 1:e]:
    m = re.match(r'^(\s*)while True do\s*(.*)$', l)
    if m and m.group(2).strip():
        body.append(m.group(1) + '{ soak: idle loop removed }')
    elif m:
        body.append(m.group(1) + 'for SoakK := 1 to %d do' % inner)
    else:
        body.append(l)
if control:
    body.insert(0, '  GetMem(SoakLeak, 64);   { soak --control: a deliberate leak }')
head = L[:b]
# A delay allocates nothing, and vTaskDelay counts TICKS: hello-s3 sleeps
# ~2,500 per pass, 25 s at 100 Hz. One tick keeps the scheduler yield and
# drops the wait (a check row that times something may then FAIL; the soak
# reads the heap, not the rows).
dly = lambda l: l if re.match(r'^\s*(procedure|function)\b', l) else \
    re.sub(r'vTaskDelay\([^;]*\)', 'vTaskDelay(1)', l)
head = [dly(l) for l in head]
body = [dly(l) for l in body]
decl = [] if any('esp_get_free_heap_size' in l for l in head) else \
    ['function esp_get_free_heap_size: LongWord; external;']
out = head + decl + ['var SoakK: Integer; SoakLeak: Pointer;', 'procedure SoakBody;', 'begin'] + body + [
    'end;', '',
    'var SoakH0, SoakH1: LongInt; SoakP: Integer;',
    'begin',
    '  SoakBody; SoakBody;',
    '  SoakH0 := LongInt(esp_get_free_heap_size);',
    '  for SoakP := 1 to %d do SoakBody;' % passes,
    '  SoakH1 := LongInt(esp_get_free_heap_size);',
    "  WriteLn('SOAK-RESULT delta=', SoakH0 - SoakH1, ' passes=%d bpp=', (SoakH0 - SoakH1) div %d);" % (passes, passes),
    "  WriteLn('SOAK-COMPLETE');",
    'end.', '']
open(path, 'w').write('\n'.join(out))
PY

# build.sh computes REPO_ROOT from its own location, which is now the stage
sed -i -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$REPO_ROOT\"|" -e "s|^ROOT=.*|ROOT=\"$REPO_ROOT\"|" build.sh
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1
if ! PXX="$PXX" bash build.sh >"$W/build.log" 2>&1; then
  echo "SOAK $EX $CHIP BUILD-FAIL"; tail -15 "$W/build.log" | sed 's/^/  | /'
  echo "SOAK-COMPLETE"; exit 1
fi

case "$CHIP" in
  esp32s3|esp32s2|esp32) QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa | head -1)" ;;
  *)                     QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 | head -1)" ;;
esac
( cd build && python -m esptool --chip "$CHIP" merge-bin -o "$W/flash.bin" @flash_args --fill-flash-size 2MB >/dev/null 2>&1 )
"$QEMU" -M "$CHIP" -drive file="$W/flash.bin",if=mtd,format=raw -nographic -serial mon:stdio -monitor none \
  >"$W/serial.log" 2>&1 &
QPID=$!
t=0
while [ $t -lt "$TIMEOUT" ] && ! grep -qa 'SOAK-COMPLETE' "$W/serial.log"; do sleep 1; t=$((t + 1)); done
kill "$QPID" 2>/dev/null || true; QPID=""
tag="$EX $CHIP"; [ "$CONTROL" = 1 ] && tag="$tag control"
r="$(tr -d '\r' < "$W/serial.log" | grep -a 'SOAK-RESULT' | head -1 || true)"
if [ -n "$r" ]; then
  echo "SOAK $tag ${r#SOAK-RESULT }"
else
  echo "SOAK $tag NO-RESULT after ${t}s; last serial lines:"
  tr -d '\r' < "$W/serial.log" | tail -8 | sed 's/^/  | /'
fi
echo "SOAK-COMPLETE"
