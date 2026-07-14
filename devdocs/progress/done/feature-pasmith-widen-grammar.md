---
prio: 65
---

# pasmith is too NARROW: 527 divergences, one bug. Csmith found dozens.

- **Type:** feature (fuzzer coverage — Track T)
- **Status:** done
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

## Log
- 2026-07-14 — **landed (Track T).** Grammar widened; the two prerequisites this ticket
  set were met first, and both mattered.

  **Prerequisite 1 — CLUSTER before filing, done as tooling, not discipline.** Findings
  now carry a signature (`<disagreement-class>_<statement-kind>`) and live in
  `tstate/fuzz/LEDGER.json`, one entry per signature. The 639 stub reports folded into
  one entry with `hits: 639`. A known signature is counted, never re-filed; a NEW one
  stops the slice (`--stop-on-new`); while anything is unfixed, slices are spaced
  `fuzz_backoff_minutes` apart and every idle tick RECHECKS the unfixed entries, so
  full-speed fuzzing resumes by itself on the fix. See `tstate/fuzz/README.md`.

  **Prerequisite 2 — order-dependent programs.** Already resolved
  ([[bug-t-pasmith-order-dependent-programs]]); the widened rungs keep the invariant:
  var/out-parameter procedures are called ONLY as statements (never inside an
  expression, where operand order is unspecified), var/out arguments are forced
  DISTINCT (two writable params aliasing one variable would make the result depend on
  the order the callee writes them), and `out` is never read in a body.

  **Rungs landed** (`--wide`, or individually): records — nested, packed, inline static
  array, inline `string[N]`, a **forward** pointer type (`PRk = ^TRk` declared before
  `TRk`, the b338 shape), a New/Dispose heap chain, whole-record copies, `with`;
  static arrays with `for..in`; enums + set types (`in`, set ops, case-of-enum,
  `for..in` over a set); `string[8]` globals and record fields; an exception class
  chain (raise a DERIVED class, catch it on a BASE one — the b339 shape, every raise
  caught by construction); procedures with var/const/out params.

  The load-bearing trick is `int_paths()`: a record field, an array element and a
  pointer deref are handed to the existing expression machinery **as variables**, so
  every operator, cast, comparison and argument position the generator already knew how
  to build immediately works through `^`, `.` and `[]` — no new expression code at all.
  Field offsets, deref resolution and copy sizes get exercised for free.

  **Gate:** 100 `--wide` seeds, 0 rejected by FPC (the generator's contract); every
  rung clean in isolation against the pxx/FPC/-O differential; 80 `--wide` seeds clean
  at HEAD once the three bugs below were dodged. Programs are ~1100 lines, deliberately.

  **Three bugs found, all filed into the owning lanes** (T owns the tool, never the
  bug) — and the distinct-causes-per-CPU-hour number, which is what this ticket was
  actually about, went from ~1 to 3 in the first run:
  - [[bug-pascal-not-of-ord-uses-boolean-negation]] (P) — `not ord(x)` computes a
    boolean not (`xor 1`) instead of a bitwise complement. Silent wrong integer. The old
    grammar could not express it: it only ever emitted `ord()` inside a cast, and it
    took a bare `ord()` leaf (which the enum rung introduced) to write the shape.
  - [[bug-pascal-shortstring-no-truncation-buffer-overrun]] (P) — `string[N] :=
    <longer>` does not truncate; it writes past the buffer and clobbers the next
    variable. Found while probing the rung, before generating a single program with it.
  - [[bug-cross-pointer-store-record-with-shortstring-field]] (A) — on
    i386/aarch64/arm32, a `string[N]` field makes EVERY store through a pointer to that
    record fail to compile.
  - [[compat-pascal-copy-of-char-literal]] (P) — surfaced by the driver change that made
    a pxx compile failure a FINDING at all: it used to be filtered out of the oracle
    groups, the survivors agreed, and the program scored *clean*. A compiler that cannot
    build valid objfpc was invisible to every fuzz slice ever run.

  All four are dodged by construction in the generator (constants marked
  `NO_SHORTSTRING_TRUNCATION`, `NO_ONE_CHAR_STRING_LITERAL`, `NO_BARE_NOT_ORD`, and
  `--shorts 0` for cross runs), each a one-line revert marked in place. Re-finding a
  ticketed bug every slice is noise — the fuzzer's job is the NEXT bug.

  **Not done, deliberately:** multi-UNIT programs (rung 2 of the direction list). It is
  the one remaining structural gap — several of our worst bugs were unit-ORDER dependent
  and are unreachable from a single-file generator — and it needs the driver to compile
  and link several units, which is a different change from widening the grammar. Filed
  as a follow-up rather than bolted on here.
- 2026-07-14 — resolved, commit HEAD.
