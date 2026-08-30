---
slug: bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2
track: B
prio: 65
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "pxx defines VER3_2_2 but its RTL declares no `TArray<T>`. FPC provides System.TArray<T> from 3.0.2 on, so real code guards its own fallback with `{$ifdef VER3_0_0}` and relies on the RTL otherwise -- rtl-generics does exactly that and dies at generics.collections.pas:135 `unknown type: TArray`. Proved by defining VER3_0_0: the error vanishes and the parse advances 79 lines."
owner: frankB
---

# B: the RTL provides no `TArray<T>`, while pxx claims to be VER3_2_2

## The gap

`grep -rn "TArray" lib/ --include=*.pas` returns **nothing**. FPC declares

```pascal
  TArray<T> = array of T;
```

in the `System` unit from 3.0.2 onward. pxx's lexer answers `VER3`, `VER3_2`
and `VER3_2_2` (`compiler/lexer.inc:1188-1190`), so to any Pascal source doing
version detection pxx *is* FPC 3.2.2 — and 3.2.2 has `TArray`.

That combination is the defect: we claim the version whose RTL provides the
type, and do not provide it.

## How real code trips on it

Library code guards its own fallback declaration on the version that lacked the
type. `library_candidates/rtl-generics/.../generics.collections.pas:56`:

```pascal
  {$ifdef VER3_0_0}
  TArray<T> = array of T;
  {$endif}
```

pxx does not define `VER3_0_0`, so the fallback is correctly skipped, and then
there is nothing to skip *to*:

```
pascal26:135: error: unknown type: TArray
  near:  ACount  SizeInt   >>> TArray  UInt32
```

`:135` is `function ToArrayImpl(ACount: SizeInt): TArray<T>; overload;`.

**The guard is not a workaround to be defeated — it is the correct FPC idiom,
and pxx answers it correctly.** The RTL is the side that is missing something.

## Proof it is the whole story at that line

Define the symbol so the unit declares the type itself:

```
$ pascal26 -dVER3_0_0 -Fu<rtl-generics/src> gcprobe.pas gco2
pascal26:214: error: unexpected token          { a DIFFERENT, later error }
```

`:135` disappears and the wall advances 79 lines. Nothing about generic ARRAY
templates is broken — the type was simply never declared. (That also disproves
the hypothesis recorded in
[[bug-p-generic-type-param-unresolved-in-class-abstract-template]] that a
generic array template fails to resolve where a generic class template
succeeds; measurements and shas are in that ticket.)

## Fix

Declare `TArray<T> = array of T;` in the RTL where the rest of the
System-unit-equivalent types live, so it is visible without a `uses`. Check
first whether pxx's generic machinery lets a bare generic alias live there —
`TArray<T>` is an alias to an anonymous `array of T`, not a class template, and
the RTL is compiled by the pinned binary.

Then re-run the probe above WITHOUT `-dVER3_0_0` and confirm `:135` clears on
its own.

Reported from Track P while working the rtl-generics corpus wall; `lib/rtl` is
Track B's file, so filed rather than taken. Blocks rung 6 of
[[feature-pascal-corpus-expansion]] behind
[[bug-p-generic-type-param-unresolved-in-class-abstract-template]].

## 2026-08-30 (frankB) — FIXED, one declaration. The wall moved 79 lines.

`TArray<T> = array of T;` added to `lib/rtl/sysutils.pas`, beside
`TStringArray`. Measured at pin **v396**, `c781fc84f`.

### The measure is the wall, not the compile

Without `-dVER3_0_0` — the real test, since that symbol was only ever the
ticket's scaffold:

| | before | after |
| --- | --- | --- |
| `generics.collections.pas` stops at | `:135 unknown type: TArray` | `:214 expected ':' before 'var'` |

**79 lines, exactly as predicted, and onto the wall frank-rust already named as
its next one.** A different error at a later line is the result; had it stayed
at `:135` the declaration would have been the wrong one.

### The first risk the ticket named, checked before writing anything

*"Check first whether pxx's generic machinery lets a bare generic alias live
there."* It does — an alias to an anonymous `array of T` declared in a unit and
instantiated from another, with both a scalar (`Integer`) and a **managed**
(`AnsiString`) element type. Both corpus spellings work: plain `TArray<T>`
(26 occurrences) and `specialize TArray<T>` (4). The two bare `TArray` hits in
the corpus are comments, not code.

### Why SysUtils, and the residual gap stated exactly

**FPC puts this in `System`**, where it is ambient and needs no `uses`. pxx has
no `lib/rtl/system.pas`; its ambient types are compiler-side, so the faithful
position is a **Track A** change. SysUtils is the closest reachable equivalent
and covers every real consumer: all **7** files in the rtl-generics corpus that
name `TArray<>` also `uses SysUtils` — checked, not assumed — and in FPC
everyone sees it through System transitively anyway.

The gap that leaves is precise and measured, not hypothesised: a unit naming
`TArray<T>` **without** `uses SysUtils` compiles under FPC and gives
`unknown type: TArray` here. **Not filed as a ticket**, because no program in
any corpus is affected and a ticket that cannot name one is a `rejected/`
ticket at prio 10 that stays in the ranker's scan forever. It is recorded in
the source comment instead, where whoever hits it will be standing.

### Gate

`make lib-test` **green** against stable v396 — the whole dashboard, since
`sysutils` is used by essentially everything and this is the one change where a
narrow check would not have been enough.

### Two findings that are NOT this ticket, both proven pre-existing by stashing

1. **`-dVER3_0_0` now HANGS** (>45 s, killed) instead of reaching `:214`.
   Identical with this change stashed, so it is not the declaration's doing —
   but this ticket's own proof-of-concept run no longer reproduces as written,
   and whoever relies on that scaffold should know. Flagged to frank-rust.
2. [[bug-p-an-alias-to-a-named-dynamic-array-type-cannot-be-indexed]] (P, p50)
   — `type TA = array of Integer; TB = TA;` and indexing a `TB` is
   `this value cannot be indexed`, while a `TA` is fine. Found while checking
   whether this declaration could break code that declares its own `TArray<T>`
   under the `{$ifdef VER3_0_0}` idiom. **It cannot**: that case fails
   identically with this change stashed, and so does a plain non-generic
   alias, which is what led to the real bug. Direct use — `var a:
   TArray<Integer>` — works, which is what the corpus does, so it does not
   block anything here.

## Log
- 2026-08-30 — resolved, commit 72d3d69eb.
