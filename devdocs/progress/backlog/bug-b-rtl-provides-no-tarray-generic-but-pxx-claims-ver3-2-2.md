---
slug: bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2
track: B
prio: 65
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "pxx defines VER3_2_2 but its RTL declares no `TArray<T>`. FPC provides System.TArray<T> from 3.0.2 on, so real code guards its own fallback with `{$ifdef VER3_0_0}` and relies on the RTL otherwise -- rtl-generics does exactly that and dies at generics.collections.pas:135 `unknown type: TArray`. Proved by defining VER3_0_0: the error vanishes and the parse advances 79 lines."
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
