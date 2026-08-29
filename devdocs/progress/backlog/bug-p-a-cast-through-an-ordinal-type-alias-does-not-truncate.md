---
track: P
prio: 70
type: bug
status: open
found: 2026-08-29
found-by: claude-N
---

# A cast through an ordinal type ALIAS does not truncate

```pascal
type
  A1 = byte;
  A2 = A1;          { alias of an alias }
  S1 = shortint;
  W1 = word;
var c: cardinal;
begin
  c := $12345678;
  WriteLn(byte(c));    { 120  — correct, both }
  WriteLn(A1(c));      { FPC 120        pxx 305419896 }
  WriteLn(A2(c));      { FPC 120        pxx 305419896 }
  WriteLn(S1(c));      { FPC 120        pxx 305419896 }
  WriteLn(W1(c));      { FPC 22136      pxx 305419896 }
end.
```

A cast written with a **builtin type name** narrows correctly. The identical cast
written with a **user-declared alias of that same builtin** passes the value
through unchanged. One concept, two paths, and only one of them narrows —
`normalise-dont-special-case.md`'s shape exactly.

The alias itself is fine: `SizeOf(A1) = 1` and `Ord(High(A1)) = 255`, matching
FPC. Only the cast fails to narrow.

## Why it hides, and why that makes it worse

```pascal
b := A1(c);          { 120 — correct: the ASSIGNMENT truncates }
WriteLn(A1(c) and 255);  { 120 — correct: the mask hides it }
```

The wrong value only escapes where the cast's result is consumed **directly** —
as an array index, a call argument, or an operand. Anywhere it lands in a typed
variable first, the store narrows it and the bug is invisible. So the shapes a
test is most likely to be written in are exactly the shapes that pass.

## Found by

`uses Generics.Hashes;` — a program whose body is `WriteLn('A')` — **segfaults
before the first statement**. FPC runs it. Rung 3 of
[[feature-pascal-corpus-oop]] ([[feature-pascal-corpus-generics]]).

The chain is worth recording because nothing along it reports an error:

1. `generics.hashes.pas:976` declares **`type ToByte = byte;`** — on non-ARM it
   is a type ALIAS, so `ToByte(x)` is a truncating cast, not a call. (The
   `{$ifdef CPUARM}` arm above it is a real masking *function*; the unit uses
   the two interchangeably, which is what makes the alias load-bearing.)
2. `InitializeCrc32ctab` indexes `crc32ctab[0, ToByte(crc)]` where `crc` is a
   full `cardinal`.
3. Without narrowing that index reaches ~4.3e9 into a `array[0..3, byte] of
   cardinal`, so the unit's initialization writes wildly out of bounds and dies.

Confirmed by substitution rather than by argument: replacing only
`type ToByte = byte;` with the unit's own ARM-path masking function makes
`uses Generics.Hashes` run clean, and `uses Generics.Defaults` — which had the
same segfault through this dependency — then **compiles and runs**. Two of this
rung's walls were this one bug.

## Scope

Every ordinal alias tested fails: `byte`, `shortint`, `word`, and an alias of an
alias. `longword` agrees with FPC only because no narrowing is required at 32
bits — it is not a passing case, it is an unobservable one.

**Not measured:** aliases of `Char`/`Boolean`/enumerated/subrange types, and
whether a `packed record` field or a `var` parameter of an alias type is
affected. Worth checking with the fix rather than assumed.

## Adjacent gap found on the way, NOT this bug

`type TMyB = type byte;` — the DISTINCT-type declaration — is rejected outright:
`error: unknown type: type`. FPC accepts it (`x := 5; TMyB(c)` prints `5 120`).
Loud, so it is a separate compat item and not folded in here; filed as
[[compat-pascal-distinct-type-declaration]].

## Gate

`make compiler/pascal26` (self-host byte-identical) + the program at the top of
this ticket matching FPC on every row, **and** `uses Generics.Hashes;` running to
completion. Add the alias table as a regression test — including the assignment
and mask rows, which pass today and are what would hide a partial fix.
