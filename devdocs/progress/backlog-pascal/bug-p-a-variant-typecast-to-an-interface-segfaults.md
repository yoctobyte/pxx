---
slug: bug-p-a-variant-typecast-to-an-interface-segfaults
title: "`IFoo(v)` on a Variant segfaults, while `g := v` is correct"
track: P
prio: 35
type: bug
blocked-by: []
status: open
created: 2026-09-09
summary: "A Variant now HOLDS an interface and reads back correctly through assignment (`g := v`), but the CAST spelling `IFoo(v)` still reinterprets the variant record and segfaults. Same shape as bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting, which fixed the scalar casts via VariantCastToTemp and deliberately scoped itself to scalars; an interface target is now a real case for it, because there is finally something correct to convert TO. Delphi code spells the read-back both ways."
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
