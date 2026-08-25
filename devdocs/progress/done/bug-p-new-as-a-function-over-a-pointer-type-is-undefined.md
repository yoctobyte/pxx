---
slug: bug-p-new-as-a-function-over-a-pointer-type-is-undefined
title: "`p := New(PRec)` — New's expression form — is `undefined variable (New)`"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "FPC's New has two spellings: the statement `New(p)` and the expression `p := New(PRec)`, which takes the pointer TYPE and hands the block back. pxx implemented the intrinsic solely in the statement parser, so the expression spelling was an undefined name. FIXED this session with a matching arm in ParseFactorCore."
---

# Measured, 2026-08-25

```pascal
type TRec = record a, b: Integer; end;  PRec = ^TRec;
var p: PRec;
begin
  p := New(PRec);        { fpc: ok — pxx: undefined variable (New) }
  p^.a := 3; p^.b := 4;
  Dispose(p);
end.
```

The statement form `New(p)` worked and always has. Only the value-returning
spelling was missing, and it is missing for a structural reason worth recording:
the intrinsic lived **only** in the statement parser, so no expression position
could reach it.

# Fix (landed 2026-08-25)

An arm in `ParseFactorCore` (`compiler/pasparser_expr.inc`) with the same
lowering the statement arm uses — `GetMem(SizeOf(pointee))` — reading the size
off the ALIAS row instead of off a variable's symbol, which is the only real
difference between the two spellings. Guarded so it can fire on nothing else: no
user `New` proc or variable in scope, a `(` must follow, and the argument must be
an identifier naming a POINTER type alias (so `New(p)` over a variable stays the
statement form and never reaches here).

Regression test `test/test_new_as_a_function_over_a_pointer_type.pas` asserts
both spellings over both a record and a scalar pointee, so the two arms cannot
drift on the size rule; `.expected` from fpc 3.2.2.

# Where it was found

[[feature-pascal-corpus-generics]] — `Result := New(PSpoofInterfacedTypeSizeObject)`
in `TComparerService.CreateInterface`, Generics.Defaults line 2074.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
