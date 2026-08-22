---
track: P
prio: 45
type: bug
blocked-by: []
status: backlog
summary: "`PInteger(p)^ := 1;` as a STATEMENT is `undefined variable (PInteger)`, while the same cast as an EXPRESSION works. Only PByte/PWord/PInt32/PInt64/PDouble work as targets -- exactly the five that happen to be declared for real in compiler/builtin/*.pas -- so the statement path resolves the name through FindTypeAlias alone and never consults BuiltinPtrNameElemTk. ~20 names affected including PChar, PCardinal, PBoolean, PNativeInt."
---

# A builtin pointer-name cast is refused as an ASSIGNMENT TARGET

Found 2026-08-22 by an FPC differential sweep (fpc 3.2.2 `-Mobjfpc -O1` vs pxx
`3dba78808`). Loud, not silent — a compile error, no wrong values.

## Symptom

```pascal
var p: Pointer;
begin
  p := GetMem(16);
  writeln(PInteger(p)^);   { works }
  PInteger(p)^ := 42;      { error: undefined variable (PInteger) }
end.
```

FPC accepts both. A user-declared `PI = ^Integer` accepts both.
`Inc(PInteger(p)^)` works. Assigning the cast to a variable first works. Only
the assignment-TARGET position fails, and the receiver does not matter — a plain
`var`, a record field and a `class var` all fail identically.

## Which names, and what that says about the cause

Every builtin pointer name, as a statement target:

| works | refused |
| --- | --- |
| `PByte` `PWord` `PInt32` `PInt64` `PDouble` | `PInteger` `PLongInt` `PCardinal` `PLongWord` `PChar` `PPointer` `PQWord` `PBoolean` `PSingle` `PShortInt` `PSmallInt` `PUInt8` `PUInt32` `PNativeInt` `PPtrInt` (and the rest of `BuiltinPtrNameElemTk`'s ~25 names) |

The working five are **exactly** the names declared as real type aliases in the
always-linked prelude (`compiler/builtin/builtinheap.pas` declares PWord, PByte,
PInt64, PInt32; `builtin.pas` declares PDouble). So they are not "supported" —
they are found by `FindTypeAlias` like any source declaration, and the statement
path never falls through to `BuiltinPtrNameElemTk` / `EnsureBuiltinPtrAlias` the
way the expression path does (`pasparser_expr.inc:5515`).

That makes this the double-case shape of
`devdocs/dev/normalise-dont-special-case.md`: one concept, two lookup paths, and
the second one stayed broken. The fix is the same one-line fallback the
expression path already has, at the statement/lvalue-target site — not a second
name table. Note `EnsureBuiltinPtrAlias`' ordering rule is load-bearing (it must
run only AFTER `FindTypeAlias` misses; registering builtins up front breaks the
self-host gate — see `bug-pascal-builtin-pointer-type-cast`), so the fallback
belongs after the alias lookup, mirroring the expression site exactly.

## Gate

`make compiler/pascal26` + a differential test over the whole name list as both
an expression and a statement target + `tools/gate.sh quick`.
