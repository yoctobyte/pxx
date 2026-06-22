#!/usr/bin/env bash
# Track B library test suite.
#
# Modes:
#   green      hard-fail curated library regressions
#   discovery  non-gating probes that should turn into Track A/B tickets
#   all        green + discovery

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PXX_STABLE="${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}"
MODE="${1:-green}"

fail=0

say() {
  printf '%s\n' "$*"
}

compiler_check() {
  if [ ! -x "$PXX_STABLE" ]; then
    say "missing pinned stable compiler: $PXX_STABLE"
    exit 1
  fi
  say "library suite pinned to: $PXX_STABLE"
}

case_out() {
  local label="$1"
  printf '/tmp/pxx_libsuite_%s' "$label"
}

run_expect() {
  local label="$1"
  local expected="$2"
  shift 2
  local out actual
  out="$(case_out "$label")"
  if ! "$PXX_STABLE" "$@" "$out" >/tmp/pxx_libsuite_"$label".compile.log 2>&1; then
    say "FAIL  $label -- compile: $(tail -1 /tmp/pxx_libsuite_"$label".compile.log)"
    fail=1
    return
  fi
  actual="$("$out")"
  if [ "$actual" = "$expected" ]; then
    say "OK    $label"
  else
    say "FAIL  $label -- output mismatch"
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    fail=1
  fi
}

run_smoke() {
  local label="$1"
  shift
  local out actual
  out="$(case_out "$label")"
  if ! "$PXX_STABLE" "$@" "$out" >/tmp/pxx_libsuite_"$label".compile.log 2>&1; then
    say "FAIL  $label -- compile: $(tail -1 /tmp/pxx_libsuite_"$label".compile.log)"
    fail=1
    return
  fi
  if ! actual="$("$out")"; then
    say "FAIL  $label -- runtime exit"
    fail=1
    return
  fi
  if [ -z "$actual" ]; then
    say "FAIL  $label -- empty output"
    fail=1
    return
  fi
  say "OK    $label"
}

probe_compile() {
  local label="$1"
  local track_hint="$2"
  shift 2
  local out log
  out="$(case_out "$label")"
  log="/tmp/pxx_libsuite_${label}.compile.log"
  if "$PXX_STABLE" "$@" "$out" >"$log" 2>&1; then
    say "OK    $label"
  else
    say "GAP   $label -- $(tail -1 "$log")"
    say "      request: $track_hint"
  fi
}

run_green() {
  say "=== library suite: green ==="
  run_expect sudoku \
    $'534678912672195348198342567859761423426853791713924856961537284287419635345286179\n987654321246173985351928746128537694634892157795461832519286473472319568863745219\n812753649943682175675491283154237896369845721287169534521974368438526917796318452' \
    "$ROOT/examples/sudoku/sudoku.pas"
  run_smoke collections -dPXX_MANAGED_STRING "$ROOT/test/test_collections.pas"
  run_smoke math "$ROOT/test/test_math.pas"
  run_expect sysutils \
    $'0\n-123456789\n10000000000\nhello\nworld\n[]\n[pad]\n42\n-7\n-1\n100\nQ\n7\nAB3Z\nab3z\nhello\nab\nbcde\nabcde\nabcde\nhello world\nstart end\nstart end\nabc\nfoobar\nx\nx\nbase\n77\nderived' \
    "$ROOT/test/lib_sysutils.pas"
  run_expect random \
    $'5 6 6 2 6 4 2 5 \n5 6 6 2 6 4 2 5 \n359 891 105 979 687 ' \
    "$ROOT/test/lib_random.pas"
  run_expect platform_posix \
    $'posix\nfiles\nsockets\nthreads\ndynlib\npal-write=3\nflush=0\ntell=2\nfile=io:2:2\nrename=0\nold-missing\nnew-readable\ndelete=0\nmkdir=0\nrmdir=0\nunsupported=-38' \
    -Fu"$ROOT/lib/rtl/platform/posix" "$ROOT/test/lib_platform.pas"
  run_expect platform_net_posix \
    $'tcp=ok\nunsupported=-38' \
    -Fu"$ROOT/lib/rtl/platform/posix" "$ROOT/test/lib_platform_net.pas"
  run_expect platform_esp_unsupported \
    $'esp-idf\nopen=-38\nread=-38\nseek=-38\nflush=-38\ndelete=-38\nrename=-38\nmkdir=-38\nrmdir=-38\nsocket=-38\nreuse=-38\nnonblock=-38\nbind=-38\nconnect=-38\nlisten=-38\naccept=-38\nrecv=-38\nsend=-38\nshutdown=-38\nsockclose=-38\nunsupported=-38' \
    --platform=esp -Fu"$ROOT/lib/rtl/platform/esp" "$ROOT/test/lib_platform_esp.pas"
  run_expect textfile_posix \
    $'alpha\nbeta\ncount=2\nio=0' \
    -Fu"$ROOT/lib/rtl/platform/posix" "$ROOT/test/lib_textfile.pas"
  run_expect directory_posix \
    $'mkdir=0\nchild=0\nlist=ok\nalpha=1\nchild=1\nalpha-file=1\nchild-dir=1\nalpha-size=1\nstat-file=1\nstat-dir=1' \
    -Fu"$ROOT/lib/rtl/platform/posix" "$ROOT/test/lib_directory.pas"
  run_expect bignum_factorial \
    $'5! = 120\n10! = 3628800\n20! = 2432902008176640000\n1000! digits      = 2568\n1000! first 10    = 4023872600\n1000! trailing 0s = 249' \
    "$ROOT/examples/bignum/factorial.pas"
  run_expect zlib \
    $'OK stored roundtrip\nOK fixed huffman\nOK dynamic huffman\nOK bad header checksum\nOK bad adler32\nOK truncated stream\nOK reserved block type' \
    "$ROOT/test/lib_zlib.pas"
  run_expect png \
    $'86\n137 80 78 71\n1\n2x2\n255,0,0,255\n0,255,0,128\n0,0,255,64\n255,255,255,0\n0\nbad chunk crc' \
    "$ROOT/test/lib_png.pas"
}

run_discovery() {
  say "=== library suite: discovery ==="
  probe_compile demo_chess \
    "Track A: support FPC empty descendant shorthand T = class(TBase); (SysUtils.Exception now exists)" \
    "$ROOT/examples/chess/chess.pas"
  probe_compile demo_adventure \
    "Track A/B boundary: expose Text/Assign default surface and dispatch ReadLn/WriteLn(file, ...) to PAL-backed textfile RTL" \
    "$ROOT/examples/adventure/adventure.pas"
  say "(discovery is non-gating; GAP lines should map to docs/progress tickets)"
}

compiler_check

case "$MODE" in
  green)
    run_green
    ;;
  discovery)
    run_discovery
    ;;
  all)
    run_green
    run_discovery
    ;;
  *)
    say "usage: tools/library_suite.sh [green|discovery|all]"
    exit 2
    ;;
esac

if [ "$fail" -ne 0 ]; then
  exit 1
fi
