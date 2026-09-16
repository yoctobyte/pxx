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
summary: "`procedure P(var x: Int64)` called with a `LongInt` actual COMPILES, and P then writes eight bytes into the caller's four-byte variable, destroying the adjacent local. fpc refuses the same call: `Call by var for arg no. 1 has to match exactly: Got \"LongInt\" expected \"Int64\"`. Eight-line repro below prints `a=-1 guard=-1` -- the sentinel was never passed to anything. This is memory corruption from ordinary, fpc-idiomatic code with NO diagnostic at any stage, and the damage lands on whichever local the frame happens to put next, so the symptom moves between builds and does not point at the call. It also silently decides OVERLOAD RESOLUTION: widening is treated as compatible, so with several widths declared the FIRST declared compatible row wins and swallows every narrower actual -- which is how `lib/rtl/textfile.pas`'s `BlockRead(f, buf, n, c)` with `c: Integer` (the spelling fpc's own charset.pp uses) corrupted the caller's length variable. That RTL surface was repaired on 2026-09-16 by publishing fpc's four count widths narrowest-first, and `test/lib_blockio.pas` pins it -- but the ordering is a property of this bug, not a fix for it, and it will stop being needed the day resolution refuses a narrowing/widening var actual."
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
2. **Overload resolution.** Because widening counts as compatible, several
   overloads differing only in a var parameter's width are ALL viable, and the
   winner is decided by declaration order rather than by the actual's type.
   Measured: with `var numRead: Int64` declared first, `LongInt`, `Integer` and
   `Word` actuals all bound to it; moving the narrow rows in front made all
   five widths resolve correctly. Fixing (1) makes this fall out, and makes the
   ordering in `lib/rtl/textfile.pas` unnecessary rather than load-bearing.

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
