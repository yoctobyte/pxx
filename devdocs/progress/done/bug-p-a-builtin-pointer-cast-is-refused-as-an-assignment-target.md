---
track: P
prio: 45
type: bug
blocked-by: []
status: done
summary: "`PInteger(p)^ := 1;` as a STATEMENT is `undefined variable (PInteger)`, while the same cast as an EXPRESSION works. Only PByte/PWord/PInt32/PInt64/PDouble work as targets -- exactly the five that happen to be declared for real in compiler/builtin/*.pas -- so the statement path resolves the name through FindTypeAlias alone and never consults BuiltinPtrNameElemTk. ~20 names affected including PChar, PCardinal, PBoolean, PNativeInt."
owner: claude-A
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

---

# Resolved 2026-08-24 — the one-line fallback, plus the name the table never had

The statement lvalue path (`pasparser_stmt.inc`, the "C4" block) now falls
through to `EnsureBuiltinPtrAlias` when `FindTypeAlias` misses, in that order —
the same two lines the expression site has carried, and the order is the
load-bearing part (registering the builtins up front shadows a source
declaration and silently re-types this compiler's own `PWord = ^NativeInt`,
which is `bug-pascal-builtin-pointer-type-cast`).

**`PChar` needed one thing more, and it is the reason not to "just register the
names".** PChar is deliberately absent from `BuiltinPtrNameElemTk`: the
expression site lowers it as the **-2 adapter**, which skips a STRING operand's
inline length prefix. A plain `^Char` alias would have made `PChar(s)^ := 'H'`
write into the string HANDLE instead of its first character — a wrong value,
silently, where today there is a clean compile error. The statement path
therefore builds the same adapter, spelled the same way; `PChar(s)^ := 'H'`
now edits the string and matches fpc.

# Verified

- A 27-name sweep (every name in `BuiltinPtrNameElemTk` plus PChar), each
  written as `<N>(p)^ := v; WriteLn(<N>(p)^)` and diffed against fpc 3.2.2:
  **26 agree**, the 27th being `PPointer`, where fpc refuses to `WriteLn` a
  pointer at all and pxx prints 0. Before the fix, 20 of the 27 were a compile
  error.
- `test/test_builtin_pointer_cast_as_target.pas` — 11 rows including a user
  alias with a record-field chain and both PChar shapes (into a heap string and
  into raw memory). `.expected` IS fpc's output; the pinned compiler refuses the
  file outright. Green on i386 / aarch64 / arm32 / riscv32.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

# Left open, deliberately

The two lvalue paths are still two. This is the third bug of the shape "the
expression path learned something and the statement path did not", and the real
fix is for the statement path to delegate to the expression lvalue parser the
way the cast-headed-CALL case already does. Filed as
[[refactor-p-one-lvalue-path-for-statements-and-expressions]].

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
