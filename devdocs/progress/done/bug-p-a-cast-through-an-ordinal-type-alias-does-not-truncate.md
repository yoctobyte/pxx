---
track: P
prio: 70
type: bug
status: done
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

---

## FIXED 2026-08-29 — and the sibling arm, found by looking

`compiler/pasparser_expr.inc`, in the alias-cast arm. An alias whose target is
an ordinal now builds **the same node every other ordinal-cast spelling builds**
— `AN_PTR_CAST` with `ASTIVal = -1`, the width-truncating value cast — instead
of falling into the pointer reinterpret below it. `tyPointer` is excluded
explicitly, because `TypeIsOrdinal` includes it.

### The sibling: float aliases were broken the same way

Not reported, not in the corpus, found because the rule says to look:

```pascal
type TaD = double;
WriteLn(TaD(3.75):0:2);    { FPC 3.75    pxx 4615626668101337088 }
```

The IEEE bit pattern, for the same reason — a float alias also fell through to
the pointer arm. Fixed in the same place, mirroring the `Single(x)`/`Double(x)`
keyword arm exactly: a float cast is a CONVERSION, so it desugars to a hidden
temp of the cast's type plus the ordinary coercing store, not a reinterpret.

**Deliberately not filed as Track F.** The subject is the cast mechanism and the
float target is incidental — *"rank the mechanism, never the datatype"*. A float
alias answering a bit pattern is the same defect as an ordinal one answering an
unnarrowed integer, and parking it in `float/` would have left one arm of a
double case unfixed in the folder the ranker never scans.

### Microfix or overhaul — chosen deliberately, and it is the microfix

Checked the incumbents first, as instructed. They are **not** this defect through
a second door; they are three earlier doors into the same room:

| site | dispatches on | ticket |
| --- | ---: | --- |
| `:1478` | the type KEYWORD token, plus source text to split `byte` from `integer` | `bug-narrowing-typecast-rvalue-no-truncate` |
| `:1571` | the same token, `Integer` specifically | `bug-p-integer-cast-does-not-truncate-in-rvalue-position` |
| `:4074` | `OrdinalNameToTk(name)` — and **explicitly skips when `FindTypeAlias` hits** | — |
| `:6725` | `BuiltinScalarTypeKind(name)` | `bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree` |
| `:6434` | `FindTypeAlias(name)` — **this fix** | this ticket |

**Five dispatch sites for one concept**, and four of the five already build the
identical node. They differ only in *which names they recognise*. `:1323`
(unary-minus widening) is a different mechanism and not related.

The pattern is documented at the sites themselves. `:1564` says of the previous
round: *"One concept, two spellings, and the fix for the other spellings ...
deliberately left this one alone — which is precisely how the second path stays
broken."* That was written about doors 1 and 2. This is the fourth time, and
`:4074`'s guard — *"A variable, routine or user type alias of the same name still
wins"* — is the line that routed aliases away from a working narrowing cast and
into the pointer fall-through.

So: **microfix, chosen and stated.** The overhaul is one resolver
(`name -> cast kind`, consulted once) collapsing five arms into one, and it is
the right end state — but it is a refactor of a hot file three lanes read, under
a dispatch for a p70 silent wrong value that was blocking a corpus rung. Banked
rather than half-done: [[refactor-p-five-dispatch-sites-for-one-named-type-cast]].

### Verification

- `test/test_pascal_type_alias_cast.pas` — 18 rows, **expected file generated by
  running the program under FPC 3.2.2**, not transcribed from pxx. Wired into
  the Makefile. RED against `stable_linux_amd64/default/pinned`.
- The last three rows (`assigned` / `masked` / `ord`) **passed before the fix
  too**, and are in the test on purpose: they are the shapes that hide this, so
  a partial fix keeps them green. The header says so, or a later reader deletes
  them as redundant.
- Covered: byte, word, shortint, smallint, longword, integer, int64, qword,
  char (which used to **segfault**), boolean, an alias of an alias, an enum
  alias (identity preserved), a POINTER alias (unchanged — still a reinterpret),
  double and single.
- **The corpus:** `uses Generics.Hashes;` and `uses Generics.Defaults;` now
  compile **and run**, against unmodified vendored source. That is two of rung
  3's walls, and it was the reason to fix this ahead of the next rung.
- `make compiler/pascal26` converged, `c0f1661cc486`.
- `tools/gate.sh quick`.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
