#!/bin/sh
# NOISE CONTROL. Every OUTPUT-DIFFERS / RC-DIFFERS row is re-measured by running
# the OFF binary TWICE and comparing it with ITSELF. A row that differs from
# itself is the instrument, not the flip -- measured: i386 test_rtti_reg prints
# a raw RTTI dump containing a STACK ADDRESS, so ASLR alone changes 3 of 47557
# bytes, and wasmtime's trap backtrace prints wasm code offsets that shift with
# any code-size change. Both looked exactly like a flip difference.
set -u
D="$1"; shift
for pair in "$@"; do
  t=${pair%%:*}; b=${pair#*:}
  ext=""; [ "$t" = wasm32 ] && ext=.wasm
  off="$D/$t.$b.off$ext"
  [ -f "$off" ] || { echo "$t	$b	NO-BINARY"; continue; }
  timeout 60 tools/run_target.sh "$t" "$off" > "$D/noise1.out" 2>&1; r1=$?
  timeout 60 tools/run_target.sh "$t" "$off" > "$D/noise2.out" 2>&1; r2=$?
  if [ "$r1" != "$r2" ]; then echo "$t	$b	NOISE-RC	$r1/$r2"
  elif cmp -s "$D/noise1.out" "$D/noise2.out"; then echo "$t	$b	STABLE"
  else echo "$t	$b	NOISE-OUTPUT	$(cmp -l "$D/noise1.out" "$D/noise2.out" | wc -l) byte(s)"
  fi
done
