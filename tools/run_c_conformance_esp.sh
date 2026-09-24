#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# c-testsuite conformance on ESP-IDF (feature-c-esp-conformance-coverage).
#
# The desktop runner (tools/run_c_conformance.sh) runs a program and reads its
# exit status. An ESP-IDF program has neither: it is a relocatable object linked
# into an IDF image as the provider of app_main, booted under Espressif QEMU,
# and it ends by returning from a FreeRTOS task. So each test is WRAPPED:
#
#   #define main pxx_conf_main
#   #include "<NNN.c>"
#   #undef main
#   int main(void) { r = pxx_conf_main(0, 0); printf("\nPXX-CONF-EXIT %d\n", r); }
#
# and the verdict is the bytes between IDF's "Calling app_main()" and that
# marker (CR stripped) against NNN.c.expected, plus r == 0 -- the same contract
# upstream states, read off the serial console instead of a process. The call
# goes through a cast to (int, char **) because two tests take argc/argv and
# the rest take nothing; on ilp32 the extra argument registers are ignored.
#
# BUILT ONCE, RELINKED PER TEST: the IDF project is copied from
# examples/esp32/hello-c3 into a private work dir (so this never contends with
# tools/esp_run.sh's lock or a peer's run), configured once, and each test only
# re-archives main.o and re-runs ninja. QEMU is killed as soon as the marker,
# IDF's own "Returned from app_main()", or a panic appears -- a fixed timeout
# per test would be the whole cost of the run.
#
# Usage: tools/run_c_conformance_esp.sh [compiler] [--shard I/N] [--only NNN.c]
#   chip: esp32c3 (riscv32). esp32s3 is not wired: variadic C on the windowed
#   xtensa ABI is refused by the compiler, and every test reaches printf.
#
# Skips: test/c-conformance/pxx.skip (base) plus pxx.skip.esp32c3.
# Prints ESP-CONF-COMPLETE as its last line whatever the verdict, so a caller
# can tell a finished run from one that died -- grep for it, never trust a
# wrapper's exit status.
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CC="$ROOT/compiler/pascal26"
SUITE="${ESP_CONF_SUITE:-$ROOT/library_candidates/c-testsuite/tests/single-exec}"
CHIP=esp32c3
SHARD_I=0; SHARD_N=1; ONLY=""
case "${1:-}" in ''|--*) ;; *) CC="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; shift ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --shard) SHARD_I="${2%%/*}"; SHARD_N="${2##*/}"; shift ;;
    --only)  ONLY="$2"; shift ;;
    *) echo "run_c_conformance_esp: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
LABEL="test-c-conformance-$CHIP"
SKIPLIST="$ROOT/test/c-conformance/pxx.skip"
TSKIPLIST="$ROOT/test/c-conformance/pxx.skip.$CHIP"
PER_TEST_TIMEOUT="${ESP_CONF_TIMEOUT:-20}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"
QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)"

# A missing suite is NOT a pass. The desktop runner prints SKIP and exits 0,
# which makes a green there mean nothing ran; this one refuses instead.
if [ ! -f "$SUITE/00001.c" ]; then
  echo "$LABEL: NO SUITE at $SUITE (run tools/install_lib_candidates.sh c-testsuite)"
  echo "ESP-CONF-COMPLETE"
  exit 2
fi
[ -x "$CC" ] || { echo "$LABEL: compiler not built ($CC)"; echo "ESP-CONF-COMPLETE"; exit 2; }
[ -n "$QEMU" ] || { echo "$LABEL: Espressif qemu-riscv32 not found"; echo "ESP-CONF-COMPLETE"; exit 2; }
[ -f "$ESP_IDF_DIR/export.sh" ] || { echo "$LABEL: ESP-IDF not at $ESP_IDF_DIR"; echo "ESP-CONF-COMPLETE"; exit 2; }
# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pxx_c_conf_esp.XXXXXX")"
qpid=""
# QEMU never exits on its own (the app parks), so an interrupted run must take
# its emulator with it or it spins forever.
trap '[ -n "$qpid" ] && kill "$qpid" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
PROJ="$WORK/proj"
mkdir -p "$PROJ"
( cd "$ROOT/examples/esp32/hello-c3" && tar cf - --exclude=./build --exclude=./sdkconfig \
    --exclude='./main/*.o' --exclude='./main/*.a' . ) \
  | ( cd "$PROJ" && tar xf - )
# The 1 MiB stock app partition is too small for crtl + IDF on the larger tests
# (00200.c overflowed it by 0x2130 bytes -- a partition limit, not a compiler
# result), so this PRIVATE copy takes IDF's 1.5 MiB single-app table. The
# generated sdkconfig is excluded above, or the defaults would not be re-read.
echo 'CONFIG_PARTITION_TABLE_SINGLE_APP_LARGE=y' >> "$PROJ/sdkconfig.defaults"
echo "$LABEL: compiler $CC ($(sha256sum "$CC" | cut -c1-12))"

# The first link needs SOME app_main; any passing test's object will do, and
# the real per-test build below replaces it.
printf 'int main(void) { return 0; }\n' > "$WORK/seed.c"
"$CC" --target=riscv32 --platform=esp "$WORK/seed.c" "$PROJ/main/main.o" > "$WORK/cc.log" 2>&1 \
  || { echo "$LABEL: seed compile failed"; cat "$WORK/cc.log"; echo "ESP-CONF-COMPLETE"; exit 1; }
ar rcs "$PROJ/main/libpxx_app.a" "$PROJ/main/main.o"
( cd "$PROJ" && idf.py set-target "$CHIP" && idf.py build ) > "$WORK/idf.log" 2>&1 \
  || { echo "$LABEL: initial IDF build failed"; tail -30 "$WORK/idf.log"; echo "ESP-CONF-COMPLETE"; exit 1; }

pass=0; fail=0; skip=0; failed=""; idx=-1
for src in "$SUITE"/*.c; do
  name="$(basename "$src")"
  idx=$((idx+1))
  [ $((idx % SHARD_N)) = "$SHARD_I" ] || continue
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue

  reason=""
  for sl in "$SKIPLIST" "$TSKIPLIST"; do
    [ -z "$reason" ] && [ -f "$sl" ] && \
      reason="$(awk -v n="$name" '$1==n { $1=""; sub(/^[ \t]+/,""); print; exit }' "$sl")"
  done
  if [ -n "$reason" ]; then
    skip=$((skip+1)); echo "SKIP $name — $reason"; continue
  fi

  W="$WORK/wrap.c"
  {
    echo '#define main pxx_conf_main'
    echo "#include \"$src\""
    echo '#undef main'
    echo 'extern int printf(const char *, ...);'
    echo 'int main(void) {'
    echo '  int r = ((int (*)(int, char **))pxx_conf_main)(0, 0);'
    echo '  printf("\nPXX-CONF-EXIT %d\n", r);'
    echo '  return 0;'
    echo '}'
  } > "$W"
  if ! "$CC" --target=riscv32 --platform=esp -I"$ROOT/lib/crtl/include" -I"$ROOT/lib/crtl/src" \
       "$W" "$PROJ/main/main.o" > "$WORK/cc.log" 2>&1; then
    fail=$((fail+1)); failed="$failed $name(compile)"
    echo "FAIL $name — compile error:"; sed -n '1,4p' "$WORK/cc.log" | sed 's/^/    /'
    continue
  fi
  ar rcs "$PROJ/main/libpxx_app.a" "$PROJ/main/main.o"
  rm -f "$PROJ"/build/*.elf "$PROJ"/build/*.bin
  if ! ninja -C "$PROJ/build" > "$WORK/link.log" 2>&1; then
    fail=$((fail+1)); failed="$failed $name(link)"
    echo "FAIL $name — IDF link error:"
    grep -m4 -E "multiple definition|undefined reference|error:|Error:|overflow" "$WORK/link.log" | sed 's/^/    /'
    continue
  fi
  ( cd "$PROJ/build" && python -m esptool --chip "$CHIP" merge-bin -o "$WORK/flash.bin" \
      @flash_args --fill-flash-size 2MB ) > /dev/null 2>&1

  SER="$WORK/serial.txt"; : > "$SER"
  "$QEMU" -M "$CHIP" -drive file="$WORK/flash.bin",if=mtd,format=raw \
    -display none -serial file:"$SER" -monitor none > /dev/null 2>&1 &
  qpid=$!
  ticks=0; limit=$((PER_TEST_TIMEOUT * 10))
  while [ "$ticks" -lt "$limit" ]; do
    if grep -qa -e 'PXX-CONF-EXIT' -e 'Returned from app_main' -e 'Guru Meditation' \
         -e 'abort() was called' -e 'Rebooting' "$SER"; then
      sleep 0.3; break
    fi
    sleep 0.1; ticks=$((ticks+1))
  done
  kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null

  OUT="$WORK/out.txt"
  awk 'f {print} /Calling app_main\(\)/{f=1}' "$SER" | tr -d '\r' > "$WORK/raw.txt"
  rc="$(grep -a -m1 '^PXX-CONF-EXIT ' "$WORK/raw.txt" | awk '{print $2}')"
  if [ -z "$rc" ]; then
    fail=$((fail+1)); failed="$failed $name(no-exit)"
    if grep -qa -e 'Guru Meditation' -e 'abort()' "$SER"; then
      echo "FAIL $name — crashed:"; grep -a -m2 -e 'Guru Meditation' -e 'abort()' "$SER" | sed 's/^/    /'
    else
      echo "FAIL $name — no exit marker within ${PER_TEST_TIMEOUT}s"
    fi
    continue
  fi
  # Everything before the marker line, minus the one newline the wrapper put
  # in front of it.
  awk '/^PXX-CONF-EXIT /{exit} {print}' "$WORK/raw.txt" > "$OUT.lines"
  python3 - "$OUT.lines" "$OUT" <<'PYEOF'
import sys
b = open(sys.argv[1], 'rb').read()
if b.endswith(b'\n'): b = b[:-1]
open(sys.argv[2], 'wb').write(b)
PYEOF
  if [ "$rc" != "0" ]; then
    fail=$((fail+1)); failed="$failed $name(exit=$rc)"
    echo "FAIL $name — main returned $rc (want 0)"; continue
  fi
  if ! cmp -s "$OUT" "$src.expected"; then
    fail=$((fail+1)); failed="$failed $name(output)"
    echo "FAIL $name — output mismatch:"
    diff -u "$src.expected" "$OUT" | sed -n '1,8p' | sed 's/^/    /'
    continue
  fi
  pass=$((pass+1))
  echo "PASS $name"
done

echo "$LABEL: $pass pass, $fail fail, $skip skip (of $((pass+fail+skip)))"
[ "$fail" = "0" ] || echo "$LABEL: FAILURES:$failed"
echo "ESP-CONF-COMPLETE"
[ "$fail" = "0" ]
