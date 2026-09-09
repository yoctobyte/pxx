---
slug: bug-p-a-variant-typecast-to-an-interface-segfaults
title: "`IFoo(v)` on a Variant segfaults, while `g := v` is correct"
track: P
prio: 35
type: bug
blocked-by: []
status: done
created: 2026-09-09
owner: frankH
summary: "DONE. `IFoo(v)` on a Variant CONVERTS instead of reinterpreting the 16-byte record, in assignment and in expression position (`IFoo(v).M(x)`), with an EMPTY slot yielding nil and any other payload halting 220 -- the same split PXXIntfFromVariant already implemented for `g := v`. The cast built AN_CLASS_CAST typed tyClass, which is RIGHT for `IFoo(p)` (a hard reinterpret of a pointer-shaped container, how FPC spells recovering an interface) and wrong for a variant, which is not pointer-shaped: the tag word reached the ARC path as an instance. Fixed with VariantCastToIntfTemp, the interface twin of VariantCastToTemp -- keyed on the REC ID, because an interface is tyRecord to a kind test. Two shared facts had to be spelled at sites that had never been asked: ResolveNodeRec had no arm for the sequencing node (it answered REC_NONE, so the conversion temp reached the interface ARC assign arm as not-an-interface and took a raw record copy with no retain), and that arm did not list the sequencing node either. Test fpc-identical on six rows including the destructor count, on five targets. One measured lifetime divergence recorded below and deliberately not chased."
owner: frankH
---

# `IFoo(v)` segfaults where `g := v` works

```pascal
{$mode objfpc}{$H+}
type IFoo = interface ['{A0000000-0000-0000-0000-000000000001}'] procedure F; end;
var v: Variant; g: IFoo;
begin
  v := SomeImpl;   { correct since bug-p-a-variant-cannot-hold-an-interface }
  g := v;          { correct: PXXIntfFromVariant, ARC-correct, nil for EMPTY }
  g := IFoo(v);    { SIGSEGV — the 16-byte variant record read as an instance }
end.
```

Measured 2026-09-09 on the repro that closed
[[bug-p-a-variant-cannot-hold-an-interface]]: with `g := IFoo(w)` the program
dies at the cast; changing exactly that one line to `g := w` prints the whole
expected sequence and destroys the object exactly once.

## Why it is the older ticket's remainder and not a new mechanism

[[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]] is
`done/`: it routed the SCALAR casts (`Int64(v)`, `Double(v)`, `Char(v)`,
`Boolean(v)`, `Byte(v)`, `LongWord(v)`, `Integer(v)`) through
`VariantCastToTemp`, which converts instead of punning. Scoping it to scalars
was right at the time — an interface in a variant was a compile error, so there
was nothing to convert to. That premise is now retired.

`IFoo(v)` does not reach `VariantCastToTemp` at all: it is an
IDENTIFIER-spelled cast to a user type, which builds an `AN_PTR_CAST` (the
ordinal/pointer pun) rather than going through the `tkChar_T` / `tkBoolean_T`
style arms in `pasparser_expr.inc` where the variant question is asked. So the
work is to ask it on that path too, with `PXXIntfFromVariant` into a temp as the
conversion — the runtime half already exists and is tested.

## What "correct" means here, already measured

fpc 3.2.2, for an interface target:

    Unassigned  ->  nil, no exception
    Null        ->  EVariantTypeCastError
    a string    ->  EVariantTypeCastError

`PXXIntfFromVariant` already implements exactly that split (nil for VT_EMPTY,
`Halt(220)` otherwise), so a cast routed into it inherits the right answer with
no new runtime.

## Guard

`test/test_variant_holds_interface.pas` is the assignment-spelled version and is
green on five targets. The cast rows belong in the same file, added when this
lands — the destructor-count discipline there is what makes an ARC regression
visible at all.


## 2026-09-09 (frankH) — DONE

Fixed by `VariantCastToIntfTemp` in `pasparser_expr.inc`, the interface twin of
`VariantCastToTemp`. It cannot reuse that routine: `VariantCastToTemp`
allocates its temp by TTypeKind and gates on `IRVariantUnboxKind`, and an
interface is `tyRecord` to both — indistinguishable there from a plain record,
which must keep reinterpreting. So the temp is allocated by REC ID and the
store is an ordinary interface-target assignment, which the lowering already
turns into `PXXIntfFromVariant`. No new runtime.

### The two facts that had never been asked at the sites that needed them

The conversion materialises its result through the sequencing node
(`AN_STR_FROM_CHAR`, `Left = the store, Right = the read`). Three places
already knew that a sequencing node's result is an lvalue — `IRLowerAST`,
`IRLowerAddress`, and the assignment's own `rhsIsLValue` test. Two more did
not, and each failed silently in its own way:

- **`ResolveNodeRec` had no arm for it** and answered `REC_NONE`. The interface
  ARC assign arm asks that question, so a conversion temp of RECORD type
  arrived as "not an interface" and fell through to a raw record copy: the
  destination got the pointer with NO retain while the temp's scope exit
  released it, so the object died at the end of the statement.
- **The ARC assign arm's kind list** did not include it either. Both had to be
  added; fixing one would have moved the failure without removing it.

A fourth question about one node kind, asked in four places, three of which
knew the answer. `devdocs/dev/normalise-dont-special-case.md` is about the
version of this where the arms disagree; this is the version where a later
consumer simply never asked.

### The parse error that named the wrong token

The first version exited before the selector walk, so `IFoo(v).Twice(4)`
failed with `near: IFoo ( v ) >>> . Twice (` — a parse error pointing at the
dot, one token after the arm that had declined to look at it. The reinterpret
path below runs `ParseClassRecordSelectors`; the conversion path now does too.

### The lifetime divergence, measured and deliberately kept

`test_variant_cast_to_interface` is byte-identical to fpc 3.2.2 on all six
rows, destructor count included. **That agreement is partly masking**, and the
masking is worth writing down: the file's row 2 uses the cast in expression
position, which materialises a temp under both compilers. Remove it and the
pure-assignment shape disagrees:

```pascal
procedure Run;
var v: Variant; f, g: IFoo;
begin
  f := TImpl.Create;  v := f;  f := nil;
  g := IFoo(v);
  v := 0;
  g := nil;
  WriteLn('destroyed=', Destroyed);   { fpc: 1   pxx: 0, then 1 at scope exit }
end;
```

pxx's conversion materialises an OWNING temp and releases it at scope exit —
the same model `obj as IFoo` already uses (`IRMaterializeIntfCast` retains its
temp; scope exit releases it). Matching fpc for one of the two casts would give
the two spellings different lifetime rules, which is the shape this ticket was
filed about in the first place. The object lives LONGER, never shorter: no
program can observe a freed object through this, and CLAUDE.md's test is the
value in its declared type, which agrees.

Neither compiler finalizes a program-scope interface local at exit (measured
both ways), so at program scope the temp keeps the object to process end. Same
in fpc for its own program-scope interface variables.

### Also swept

The AST slot-write census (`tools/ast_slot_overloads.py`) picked up the three
new child writes and was updated with `--update`; all three are genuine node
children, which is what that snapshot exists to confirm.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a4b9050f1.
