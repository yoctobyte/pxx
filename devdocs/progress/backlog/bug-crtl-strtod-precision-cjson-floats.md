---
prio: 60
---
# crtl strtod/printf-%g precision: cJSON floats drift by 1 ulp (tstate red)

- **Type:** bug (crtl numeric). Track B (library) / Track C shared surface.
- **Found:** 2026-07-07 by the Track T watcher — test-cjson went red the
  moment the cjson corpus tree was first installed (STILL-RED across SHAs,
  not a compiler regression; first report 20260707T191712Z-87ce0f6-borg).

## Symptom
`-0.0625` (exactly representable) round-trips as `-0.062500000000000008`:
    -{"delta":-0.0625, ...}
    +{"delta":-0.062500000000000008, ...}
cJSON's print_number tries %1.15g, reparses with strtod, and falls back to
%1.17g when the reparse mismatches. A 1-ulp-inexact crtl strtod (or %g
formatting) forces the %1.17g path and the long digits leak out.

## Same family, second sighting
tcc-by-pxx vs tcc-by-gcc: one 8-byte .data.ro constant differs when
compiling tccpp.c (feature-c-corpus-tcc residual notes, 2026-07-07) — a
host strtod difference embedded in emitted rodata. One fix should clear
both.

## Repro
    tools/testmgr.py --tier full --job 'test-cjson#00'
or standalone: crtl strtod("-0.0625") vs glibc — compare bit patterns
(compare as int64, not printf).

## Direction
crtl strtod likely accumulates via repeated multiplication (decimal
mantissa * 10^-k) instead of exact integer scaling — check
lib/crtl double parsing; correctly-rounded shortest-path for values with
few digits is cheap (integer mantissa + exact power-of-two/five split).
%g formatting may have the mirror issue.

## Gate
test-cjson green (tstate confirms), tcc .data.ro residual re-checked,
lua/zlib/sqlite stay green, bXXX repro test.
