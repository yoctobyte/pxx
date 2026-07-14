---
prio: 65
---

# pasmith is too NARROW: 527 divergences, one bug. Csmith found dozens.

- **Type:** feature (fuzzer coverage — Track T)
- **Status:** working
  attributed to a single defect ([[bug-pascal-case-selector-multiple-evaluation]]).

## The observation
Track T's pasmith ran for a day and produced **527 divergence reports against FPC**. Every
one of them was **the same bug**. Meanwhile csmith, on the C frontend, found **dozens of
distinct bugs** — several of them silent ones the real corpora (sqlite, lua, zlib, tcc)
could never reach ([[project_csmith_fuzzer_findings]]).

A fuzzer that reports one bug 527 times is not finding bugs; it is finding *a* bug, loudly.
The interesting number is DISTINCT causes per CPU-hour, and pasmith's is currently ~1.

## What the clustering already tells us it is NOT missing
When the case-selector bug was hoisted away, pxx reproduced FPC's checksum EXACTLY on
programs saturated with mixed-width `shortint/byte/word/smallint/longword/qword/int64`
arithmetic, `{$Q-}{$R-}` wraparound, casts, `not`, `xor`, and shifts. So the integer model
is genuinely solid — that is a real result, and it says the current grammar is *mined out*,
not that the compiler is clean.

## Where the bugs we actually shipped this month lived
Look at what pasmith could never have generated. Every one of these was a real, silent bug:

- **forward pointer types** — `PNode = ^TNode` ahead of TNode; fields past a deref resolved
  at offset 0 (b338). Needs: records, pointers to records, `^` chains, linked structures.
- **exception class matching across units** — `on E: T` missed later-unit descendants
  (b339). Needs: multiple UNITS, exception hierarchies, raise/except.
- **enum type identity** — cross-enum assignment took the ordinal silently (b342). Needs:
  several enum types in one program, and assignments between them.
- **frozen strings** (`string[N]`) — empty on riscv32 (b345). Needs: `string[N]`,
  shortstring, passing them to managed-string params.
- **member visibility** — `private` is not enforced at all (13 of 17 conformance reds).
- **case-of-string**, `with`, `for..in`, sets, variants, class methods, properties,
  interfaces, method pointers, `var`/`const`/`out` params, open arrays, nested routines.

pasmith today emits: globals of scalar types, a few functions, `case`, `if`, arithmetic,
and (per twatch's argv) some classes and strings. That is a thin slice of the dialect the
compiler actually implements — which is exactly why it keeps re-finding the same statement.

## Direction
Widen the grammar, in rough value order (each item is a bug class we have SHIPPED before):

1. **records + pointers-to-records + `^` chains** (forward-declared), and `with`.
2. **multi-UNIT programs** — several of our worst bugs were unit-ORDER dependent and are
   structurally unreachable in a single-file generator.
3. **exceptions**: class hierarchies, `raise`, `try/except/finally`, re-raise.
4. **strings beyond ansistring**: `string[N]`, shortstring, char, and conversions between
   them; `case` of string.
5. **enums + sets + subranges**, including several enum types in scope at once.
6. **parameter modes**: `var` / `const` / `out`, open arrays, arrays of const.
7. **OO**: virtual/override, properties, class methods, interfaces, method pointers.
8. **control flow**: `for..in`, nested loops with `break`/`continue`, nested routines.

Keep the existing checksum oracle (`Mix` over all live state) — it works; it is the input
grammar that is starving it.

## Two prerequisites (else the widening just makes more noise)
- Fix [[bug-t-pasmith-order-dependent-programs]] FIRST: the generator currently manufactures
  legal-but-unspecified programs (~3% of divergences), and a wider grammar will manufacture
  more of them (evaluation order, aliasing, uninitialised reads).
- **CLUSTER before filing.** 527 stub tickets for one bug is the failure mode this whole
  sweep just cleaned up. Reduce-and-dedupe, then file one ticket per distinct cause.

## Gate
A fuzzing run that surfaces **distinct** root causes, and a corpus that stays attributable:
every filed report maps to a named cause or is explicitly unattributed.
