---
track: A
prio: 35
type: refactor
blocked-by: []
status: done
summary: "ConstIntCastWidth is a third copy of the builtin type-name table -- name to width+signedness, for const-expression casts -- and it carries the same longint/nativeint disagreements that bug-a-the-builtin-type-name-table-exists-twice just settled in the other two. Not a bug today: nothing observably differs. It is the count that is the problem."
owner: frankC
---

# `ConstIntCastWidth` is the third copy of the builtin type-name table

Split out 2026-08-24 while merging the other two in
[[bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree]].

`ConstIntCastWidth` (`compiler/pasparser_expr.inc` ~8951) maps a type name to
`bytes` + `signed` for a cast inside a CONSTANT expression:

```pascal
if CaseEqual(nm, 'int64') or CaseEqual(nm, 'nativeint') or CaseEqual(nm, 'ptrint') then begin bytes := 8; signed := True; end
...
else if CaseEqual(nm, 'integer') or CaseEqual(nm, 'longint') then begin bytes := 4; signed := True; end
```

Note `nativeint` = 8 bytes unconditionally: the same claim the runtime cast
chain used to make, and the one just corrected there because NativeInt is
pointer-sized by definition and 8 is false on every 32-bit target. Here it is
probably harmless — a const expression is folded at compile time into a value,
and a const wider than the target's pointer is not a shape anyone writes — but
"probably harmless" is what the runtime chain was too, right up until someone
wrote `SizeOf(NativeInt(x))`.

## Why it was not merged in that pass

It answers a different question. `BuiltinScalarTypeKind` returns a KIND; this
returns a width and a signedness, and it is reached from the constant folder,
not the type system. Merging it means either deriving `bytes`/`signed` from the
kind (`TypeSize` / `TypeSigned` already exist and would do it) or giving the
shared table a second entry point. That is a real design call, and folding it
into a fix for a different ticket would have made both harder to revert.

## The actual argument for doing it

Three mechanisms for one concept. `devdocs/dev/root-cause-over-microfix.md` is
explicit: *two is a smell, three is a design flaw.* The merge just done took it
from three to two. This takes it to one.

## Suggested shape

`ConstIntCastWidth` becomes: `tk := BuiltinScalarTypeKind(nm); if tk is an
integer-family kind then bytes := TypeSize(tk); signed := TypeSigned(tk)`.
Watch the two places it deliberately differs from the type table before
assuming a pure substitution:

- it accepts `char` as `bytes := 1; signed := False`, which the kind table
  answers as `tyChar` (also one byte, unsigned — probably fine, verify);
- it REJECTS the float and string names by returning False, and the caller
  relies on that to fall through to `ConstAliasCastWidth`. A kind-driven
  version must reject exactly the same set, not "everything that is not
  ordinal" — `tyPointer` is ordinal by `TypeIsOrdinal` and is not in this
  table today.

## Gate

Track A's, plus a const-expression differential against fpc 3.2.2 over the same
name list (`const C = Byte($1FF);` and friends, including the signed narrowing
rows), plus self-host byte-identical.

## Done 2026-09-02 — and it WAS observably wrong

This ticket said *"probably harmless — a const expression is folded at compile
time into a value, and a const wider than the target's pointer is not a shape
anyone writes"*, and flagged `nativeint = 8 unconditionally` as the suspect
line. The suspicion was right and the "probably harmless" was not. Measured on
three targets, one program, no oracle needed:

```pascal
const A = NativeInt(4294967296 + 5);
var   a: NativeInt;  a := 4294967296 + 5;
```

| target | ptr | const fold | runtime cast |
| --- | ---: | ---: | ---: |
| i386, arm32, riscv32 | 4 | **4294967301** | 5 |
| x86-64 | 8 | 4294967301 | 4294967301 |

The same cast in the same program folded two ways, and the const one produced a
value that does not fit the type on that target. All four pointer-sized names
(`NativeInt`, `PtrInt`, `NativeUInt`, `PtrUInt`), signed and unsigned. `Integer`
agrees everywhere, which is the control.

**x86-64 could never show it**, which is why it read as harmless: there 8 is the
right answer, so the host tier passes every row either way. The prediction in
this ticket — *"'probably harmless' is what the runtime chain was too, right up
until someone wrote `SizeOf(NativeInt(x))`"* — was accurate, and the trigger
turned out to be a target rather than a spelling.

## The merge

`ConstIntCastWidth` now derives from `BuiltinScalarTypeKind` and answers the
width question with `TypeSlotSize` / `TypeSigned`. The ticket's own framing was
the obstacle — *"it answers a different question, a width and a signedness
rather than a kind"* — and that is true of the ANSWER but not of the TABLE: the
name-to-kind mapping was never the part that had to be duplicated, and the two
helpers already turn a kind into exactly this answer. Three mechanisms for one
concept becomes one.

The accepted KINDS stay an explicit closed set rather than `TypeIsOrdinal`,
which would newly admit Boolean and enums. That is a deliberate boundary: this
is a widths-of-the-integer-family question.

Deriving also picks up `sizeint`/`sizeuint`, which the shared table has always
known and the private list never accepted — `const K = SizeInt(x)` was simply
refused with "not a constant".

## Verified

`test/test_const_cast_width_matches_runtime.pas`. **The assertion is AGREEMENT
between the const fold and the runtime cast**, not a per-target constant, so the
file carries no expected widths and cannot be satisfied by a table that is
self-consistently wrong; the width is separately checked against `SizeOf` of the
type, which is the independent quantity. Green on x86-64, i386, arm32 and
riscv32, printing the correct different answers on each.

Two positive controls, because the change has two halves:
- the **pinned** compiler REFUSES TO BUILD the test — `SizeInt(W)`, "not a
  constant" — which is the merge's second half;
- on the smaller probe pinned does build, pinned/i386 folds all four
  pointer-sized rows to 4294967301 against a runtime 5, with `Integer` agreeing
  at 5.

`gate.sh quick` GREEN, FPC seed canary PASS.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0ba16eb2a.
