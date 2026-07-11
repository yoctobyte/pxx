---
prio: 40
---

# unicodestring/widestring: types not really supported (decls "work", semantics don't)

- **Type:** bug / gap (Pascal frontend) — Track P
- **Status:** backlog — filed 2026-07-11 while resolving
  [[bug-case-of-string-segfault-and-label-validation]]
- **Owner:** —

## Symptom

`var w: widestring;` / `var u: unicodestring;` parse, but the variables do not
behave as strings:

- `writeln(w)` after `w := 'abc'` prints an integer (e.g. `4226338`) — the
  value model treats it as a machine word, not a string.
- `case u of 'aba'..'daa': ...` fails with `case label does not match the
  ordinal selector type` because the selector's IR type is not
  tyString/tyAnsiString.

## Impact

The entire remaining tcase conformance cluster (20 tests: tcase0, 12–18,
24–25, 28–34, 40–41, 44) fails ONLY on the `case my_str_uni of` /
`case us of` sections — the string/ansistring/widestring sections of those
same tests pass. Burning this gap likely converts most of them.

## Sketch

Decide the model first: FPC's unicodestring is UTF-16 + refcount, widestring
likewise (COM BSTR on Windows). Cheapest useful rung: alias both to
AnsiString (byte semantics, as the suite's ASCII-only tests exercise) and
document the divergence; the honest rung is a real UTF-16 payload type.
Aliasing must cover: assignment from literals, writeln, comparison operators,
case-of-string (works free once the type maps to tyAnsiString), indexing
(tcase44 does `my_str_uni[3]`).

## Gate

`make test` + self-host fixedpoint. Re-run
`tools/run_pascal_conformance.sh --only 'tcase*'` — expect the 20
unicodestring skip entries to burn.
