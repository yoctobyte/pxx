---
track: A
prio: 30
type: refactor
blocked-by: []
status: backlog
summary: "ConstIntCastWidth is a third copy of the builtin type-name table -- name to width+signedness, for const-expression casts -- and it carries the same longint/nativeint disagreements that bug-a-the-builtin-type-name-table-exists-twice just settled in the other two. Not a bug today: nothing observably differs. It is the count that is the problem."
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
