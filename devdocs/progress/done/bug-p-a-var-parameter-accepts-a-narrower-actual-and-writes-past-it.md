---
slug: bug-p-a-var-parameter-accepts-a-narrower-actual-and-writes-past-it
title: "A `var` parameter accepts a narrower actual and is then written at the DECLARED width"
track: P
prio: 75
type: bug
status: done
owner: "frankS"
found-by: franks-ee
created: 2026-09-16
tags: [var-parameters, overload-resolution, type-checking, memory-corruption, silent-wrong-value, fpc-corpus]
blocked-by: []
summary: "FIXED 2026-09-24 (frankS). A `var`/`out` SCALAR parameter now refuses an actual of a different STORAGE WIDTH (`CheckVarArgWidth`, asked from `IRLowerCallArg`, so every call form is covered), and overload resolution treats such a row as non-viable (`MatchArgRecMismatch`), so a converting sibling argument can no longer let declaration order pick the wider row -- fpc's exact row wins. Same-width sign mismatches (LongInt for LongWord) stay accepted: fpc-stricter, cannot corrupt. The census over examples/, lib/rtl, lib/pcl and the top-level test sources (2541 files) found ONE caller, the `Val` intrinsic with a Word `code` in lib/rtl/charset.pas -- a real overrun, fixed by marshalling each Val argument through a temp of the parameter's width."
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

## Resolution, 2026-09-24 (frankS)

- `CheckVarArgWidth` (symtab.inc), called at the top of `IRLowerCallArg`:
  explicit var/out, not untyped, not an array param, not an explicit lvalue
  cast, both sides ordinal/float, storage widths differ -> error naming the
  parameter and both widths. Pascal only (`IsPascalFrontend`, not NilPy).
- `MatchArgRecMismatch` gains the same test, so every MatchProcCall phase and
  the method matcher drop the wrong-width var row: `T(i, a)` with Int64-first
  and LongInt `var a` overloads now binds the LongInt row (fpc's answer; pin
  v423 binds Int64 and writes past `a`).
- `Val(s, v, code)`: `ValMarshalVarArg` passes `v` and `code` through temps of
  the parameter's type whenever the widths differ, width read off the NODE
  (`Val(s, r.w, c)` names a record). The pin zeroes the neighbouring field and
  reads `0.00` into a Single destination; HEAD matches fpc 3.2.2 exactly.

Census (population and binary stated so it can be re-derived): every `.pas`
under examples/, lib/rtl and lib/pcl plus the top-level `.pas` files in test/,
2541 files, compiled with compiler `e58e22b81da4` (the refusal, before the
overload and Val fixes, which can only REMOVE refusals); first error per file
only, so a file refused earlier for another reason is not seen. Hits: 1 --
`lib/rtl/charset.pas:391` (`Val` with `code: Word`), fixed as above;
`test/lib_charset.pas` 98/98 at HEAD.

Tests: test_var_param_refuses_a_narrower_variable (method spelling, must not
compile), test_var_param_width_rule_accepts_exact_and_cast (incl. the overload
row; the pin prints -1), test_val_writes_each_argument_at_its_own_width
(.expected is fpc's). All three identical on x86-64, i386, arm32, aarch64,
riscv32.

The `lib/rtl/textfile.pas` narrowest-first BlockRead ordering is no longer
load-bearing; left as is (it matches fpc's own declaration order).
