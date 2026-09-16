---
slug: bug-p-a-var-parameter-accepts-a-narrower-actual-and-writes-past-it
title: "A `var` parameter accepts a narrower actual and is then written at the DECLARED width"
track: P
prio: 75
type: bug
status: open
owner: ""
found-by: franks-ee
created: 2026-09-16
tags: [var-parameters, overload-resolution, type-checking, memory-corruption, silent-wrong-value, fpc-corpus]
blocked-by: []
summary: "`procedure P(var x: Int64)` called with a `LongInt` actual COMPILES, and P then writes eight bytes into the caller's four-byte variable, destroying the adjacent local. fpc refuses the same call: `Call by var for arg no. 1 has to match exactly: Got \"LongInt\" expected \"Int64\"`. Eight-line repro below prints `a=-1 guard=-1` -- the sentinel was never passed to anything. This is memory corruption from ordinary, fpc-idiomatic code with NO diagnostic at any stage, and the damage lands on whichever local the frame happens to put next, so the symptom moves between builds and does not point at the call. It also decides OVERLOAD RESOLUTION, and CONDITIONALLY -- which is what makes it hard to reproduce and why the first explanation of it here was wrong: a `var` parameter's exact-type row is honoured only when EVERY OTHER argument binds with NO conversion at all; ONE by-value argument needing ANY conversion -- widening or narrowing, from a variable or from a literal -- masks it, and declaration order decides instead. That is how `lib/rtl/textfile.pas`'s `BlockRead(f, buf, n, c)` with `c: Integer` (the spelling fpc's own charset.pp uses) corrupted the caller's length variable WITH THE EXACT ROW DECLARED. Repaired 2026-09-16 by publishing fpc's four count widths narrowest-first (27/27; the Int64-first control scores 24/27), pinned by `test/lib_blockio.pas` -- but the ordering is a property of this bug, not a fix for it, and it will stop being needed the day resolution refuses a narrowing/widening var actual."
---

# A `var` parameter accepts a narrower actual and is written past its end

## Repro

```pascal
program vp;
procedure TakesInt64(var x: Int64);
begin x := -1; end;
var a: LongInt; guard: LongInt;
begin
  a := 0; guard := 12345678;
  TakesInt64(a);
  WriteLn('a=', a, ' guard=', guard);
end.
```

| compiler | result |
| --- | --- |
| fpc 3.2.2 | `vp.pas(7,15) Error: Call by var for arg no. 1 has to match exactly: Got "LongInt" expected "Int64"` |
| pxx (pin v410) | compiles; prints `a=-1 guard=-1` |

`guard` is never mentioned at the call. It is destroyed because `TakesInt64`
writes `SizeOf(Int64)` bytes at `@a`, and `a` is four bytes wide.

## Why this is worse than an ordinary type-check gap

**No instrument on the normal path can see it.** The callee's own writes are
correct for its declared type; the caller's variable holds the right value
afterwards in the common case (the low half is what it wanted); and what breaks
is a DIFFERENT variable, chosen by the stack frame layout. Measured the same
day in `lib/rtl`: the same defect reached through `BlockRead` destroyed the
caller's buffer-length variable in one arrangement and its sentinel in another,
from the same source, because the two test procedures laid their frames out
differently. A bug report from either one points at the wrong place.

It is also a **silent negative for assertions**: the out-parameter the caller
actually reads comes back CORRECT, so a test that checks the returned count
passes while memory is being corrupted beside it.

## The two halves

1. **Type checking.** A `var`/`out` actual must match the formal's type
   exactly. fpc's message names the rule directly. We accept any
   assignment-compatible actual, which for a var parameter is unsound in both
   directions -- a wider formal writes past the actual, a narrower formal
   leaves the actual's high bytes stale.
2. **Overload resolution, CONDITIONALLY.** Because widening counts as
   compatible, several overloads differing only in a var parameter's width are
   all viable. The exact row nevertheless wins -- **unless some OTHER argument
   converts**, and then declaration order decides. See the matrix below; it is
   the part that was stated wrongly here when this ticket was filed. Fixing (1)
   makes this fall out, and makes the ordering in `lib/rtl/textfile.pas`
   unnecessary rather than load-bearing.

## The masking rule, measured

All rows: `procedure T(c: <type>; var a: Int64)` and `T(c: <type>; var a: <exact>)`
both declared, Int64 FIRST, `a` a narrow local with a sentinel beside it. Only
the by-value argument `c` varies.

| what the by-value argument does | var binding |
| --- | --- |
| `c: Int64` <- `Int64` variable (no conversion) | correct |
| `c: Integer` <- `Integer` variable (no conversion) | correct |
| `c: Integer` <- literal `10` (no conversion) | correct |
| `c: SmallInt` <- `SmallInt` variable (no conversion) | correct |
| `c: Int64` <- `Integer` variable (widening) | **corrupts** |
| `c: Int64` <- literal `10` (widening) | **corrupts** |
| `c: SmallInt` <- `Int64` variable (narrowing) | **corrupts** |
| `c: SmallInt` <- literal `5` (narrowing) | **corrupts** |

Two things this settles that the first reading of it got wrong:

* **It is not widening-specific.** Narrowing masks identically, and so does a
  LITERAL -- literals are typed, so `T(5, a)` against `c: SmallInt` converts.
  The rule is *any* conversion.
* **One dissenter is enough.** With three arguments: both exact -> correct;
  **one** of the two converting -> corrupts; both converting -> corrupts. The
  var row's exactness is not a precondition that gates the match, it is **one
  term in a sum** that a single conversion elsewhere outweighs. That is
  arguably a second, separable defect in how the candidate score is formed --
  it is not filed separately, because fixing (1) removes the observable either
  way and a separate ticket would rank on a mechanism nobody can reach.

**Why the obvious probe cannot see any of this:** hold the call fixed at
`P(a)` -- one argument, nothing to convert -- and vary the DECLARATION order,
and every arrangement behaves correctly, because the single shape being varied
is the one shape that cannot exhibit the effect. A peer reproduced exactly that
and concluded order decides nothing. The route, not the isolation, is what
needs varying here (CLAUDE.md, "isolation guards the RUN, not the ROUTE").

## Blast radius

`var`-parameter surfaces where callers legitimately hold a narrower type are
where this bites, and the RTL publishes several: `BlockRead`/`BlockWrite`
(repaired), and every `var ...: Int64` in an interface that real code may call
with an `Integer`. This is not a search that was completed -- the repair above
covered the one the FPC corpus walked into. A census of `var` parameters whose
declared type is wider than 32 bits belongs with this fix, not before it.

## Not a workaround note

Per CLAUDE.md the RTL change that went in beside this ticket is deliberately
NOT a compiler-appeasement workaround: it publishes the overload set FPC itself
publishes, so the platonic call `BlockRead(f, buf, n, c)` with `c: Integer`
becomes correct rather than merely accepted. The narrowest-first ORDERING is
the part that exists only because of this bug, and it is commented as such in
`lib/rtl/textfile.pas` and pinned by `test/lib_blockio.pas`.
