# `too many array constant elements` — Synapse `synautil` wall

- **Type:** bug/limit (parser capacity) — Track A
- **Status:** done — fixed 2026-07-01, pin v130
- **Opened:** 2026-06-30 (found in triage; new wall past the now-fixed blockers)

## Resolution

Not a capacity ceiling at all — the ticket's "bump a MAX_*" direction was
based on an incomplete read of the error. The real bug: `ParseVarSection`'s
array-initializer parser (`var X: array[..] of T = (...)`, a *separate*
implementation from `ParseConstSection`'s `const X: array[..] of T = (...)`
one) is a flat, single-level comma-list parser with **no nested-paren
tracking at all** — any 2+-dimensional `var` array initializer
(`array[0..6,1..12] of String`, exactly Synapse's `MyMonthNames` table)
broke structurally, either misparsing outright or (after a first fix pass)
mis-consuming multi-character string literals and racing past the real
element count.

Two layered fixes, both in `compiler/parser.inc`'s `ParseVarSection`:

1. **Nested-paren support.** Replaced the flat `repeat ... until not
   Eat(tkComma)` loop with the same paren-depth-tracked `while` loop
   `ParseConstSection` already uses (`initDepth`, mirroring `ParseConstSection`'s
   `cDepth`) — leaves still parse via the existing `ParseInitVal`, only the
   *structure* around them changed. Fixes N-D initializers for ordinal types.
2. **Multi-character string literals.** `ParseInitVal`/`ConstEval` has the
   same "doesn't consume a multi-char string token" bug already fixed for
   `ParseConstSection` (see [[bug-const-array-of-ansistring-literal-too-many-elements]])
   but never mirrored into `ParseVarSection` — so any `String`/`AnsiString`
   array element with more than one character caused the loop to re-read the
   same unconsumed token repeatedly, racing `initElem` past the real bound
   and firing `too many array initializer elements` on a *correctly-sized*
   initializer. Fixed by capturing the string literal's span directly (same
   `PendingInitKind=1` mechanism `ParseConstSection` uses) instead of routing
   through `ParseInitVal` for string-typed elements.

Verified against the real `external/synapse/synautil.pas`: both the original
`too many array constant elements` wall and the follow-up `too many array
initializer elements` (surfaced mid-fix, same root cause) are gone; compile
now proceeds to a genuinely separate, unrelated wall (`DecodeDate` undefined —
filed as [[feature-sysutils-decodedate-missing]], per this ticket's own
acceptance criterion "the next wall, if any, is identified").

Regression test `test/test_var_nd_array_string_init.pas` covers 2-D ordinal
and 2-D `String` arrays (multi-char literals) plus the existing 1-D
single-char-string case, wired into `make test`. Self-host byte-identical
(no generation lag), full `make test` green, `make stabilize` green.

## Symptom

`uses synautil; --mimic-fpc` (Synapse) now compiles past its two former blockers
(bug-chr-builtin-shadows-param-name, bug-consteval-named-type-cast, both done) and
hits: `error: too many array constant elements`. A large typed-array constant
(lookup table) exceeds a fixed `MAX_*` element ceiling in the array-constant parser.

## Direction

Find the `too many array constant elements` Error site (parser array-constant
path) and the `MAX_*` it checks; bump it (interim, like the other capacity bumps),
or make it dynamic ([[feature-dynamic-compiler-tables]]). Then re-probe synautil
for the next wall. Advances [[feature-synapse-compile-check]].

## Acceptance

`synautil` (and other large array-const sources) compile past this limit; the next
wall (if any) is identified; self-host byte-identical.
