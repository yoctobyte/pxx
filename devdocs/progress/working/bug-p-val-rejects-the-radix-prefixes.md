---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`Val('$ff', v, code)` answered 0 with code=1 — none of FPC's radix prefixes ($ff, xFF, 0xFF, &17, %1011) were accepted, and `$` is how Pascal itself spells hex. `Val(s, v)`, the two-argument form, was refused outright."
---

# Val rejects the radix prefixes, and its `code` argument is not optional

- **Type:** bug (silent wrong value + refusal, FPC-compat) — **Track P**;
  touches `compiler/builtin/builtin.pas` and the shared `compiler/parser.inc`,
  so it runs under Track A's gate and needs a re-pin.
- **Found:** 2026-08-16, by an FPC-differential sweep over the RTL surface.

## Measured (before)

```
Val('$ff', v, c)     fpc 255 / 0     pxx 0 / 1
Val('xFF', v, c)     fpc 255 / 0     pxx 0 / 1
Val('0xFF', v, c)    fpc 255 / 0     pxx 0 / 2
Val('&17', v, c)     fpc  15 / 0     pxx 0 / 1
Val('%1011', v, c)   fpc  11 / 0     pxx 0 / 1
Val('7', i)          fpc 7           pxx "Expected: ,"
```

The silent half is the dangerous one: a caller that ignores `code` — which is
most of them, and is exactly why the two-argument form exists — read a 0.

## Fix

- **`Val` (builtin.pas):** a radix-prefix step after the sign, and a digit loop
  that takes a value per base (hex letters included). Overflow WRAPS for hex,
  as FPC's does — `$FFFFFFFFFFFFFFFF` is -1, not an error.
- **The parser's `Val` intercept:** `code` is optional; when it is absent the
  call gets a hidden temp. Measured against FPC first: the two-argument form
  behaves exactly like the three-argument one with the code discarded — a
  failed conversion leaves the destination 0 and raises nothing — so there is
  no error path to invent.

The failure POSITIONS are part of the contract and are asserted too: a bare
prefix with no digits stops one past itself (`'$'` -> code 2), and `'$1g'` ->
code 3.

## Result

`test/test_val_radix_and_optional_code.pas` — 19 conversion rows plus the four
optional-code shapes (int, float, QWord, and a failed one) — prints
`total ok 23 / 23` under both FPC 3.2.2 and pxx.

## Gate

`make compiler/pascal26` + the test under both compilers + `tools/gate.sh
quick` — GREEN. A `compiler/builtin` change, so `make stabilize-fast && make
pin` follows.
