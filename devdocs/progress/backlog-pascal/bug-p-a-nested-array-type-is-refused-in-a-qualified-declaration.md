---
slug: bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration
title: "`var a: TOwn.TPArr` is refused for a nested ARRAY type, while `var a: TPArr` and `var r: TOwn.TPRec` both work"
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-07
summary: "A type declared `TPArr = array[0..3] of LongInt` inside a class body resolves under its BARE name (`var a: TPArr` compiles and indexes) and under NO qualified name: `var a: TOwn.TPArr` compiles the declaration but leaves `a` non-indexable -- `this value cannot be indexed -- only arrays, strings and pointers can (a)`. The sibling nested RECORD (`var r: TOwn.TPRec`) is correct through the same qualified spelling in the same program, which is what localises this to the ARRAY arm of ParseTypeKindInner rather than to EatQualifiedTypePrefix: the strip runs (there is no parse error on the `.`) and the name that comes out of it does not reach FindArrayType. fpc 3.2.2 prints `arr = 42 rec = 7 size = 16`. Measured 2026-09-07 at compiler 2691706add55, alongside the qualified-CAST fix, which is a different position and is now closed."
---

# Repro

```pascal
program g1; {$mode objfpc}{$H+}
type
  TOwn = class
  type
    TPArr = array[0..3] of LongInt;
    TPRec = record a, b: LongInt; end;
  end;
var a: TOwn.TPArr; r: TOwn.TPRec;
begin
  a[0] := 42; r.a := 7;
  WriteLn('arr = ', a[0], ' rec = ', r.a, ' size = ', SizeOf(a));
end.
```

fpc 3.2.2: `arr = 42 rec = 7 size = 16`.
pxx: `pascal26:10: error: this value cannot be indexed — only arrays, strings and
pointers can (a)`, twice.

# What already works, which is the whole localisation

| spelling | pxx |
| --- | --- |
| `var a: TPArr` (bare, from outside the class) | works, indexes, right size |
| `var r: TOwn.TPRec` | works |
| `TOwn.TPArr(raw)[0]` — the qualified CAST | works (closed 2026-09-07) |
| `var a: TOwn.TPArr` | declaration accepted, value not an array |

The declaration does not FAIL, it under-resolves: no diagnostic at the
declaration, and the error arrives at the first `[`. That is the shape a
fallthrough-to-a-default produces, not a refusal.

# Where to look, and the trap next door

`EatQualifiedTypePrefix` is not the suspect — it is shared with the record
spelling above, which is right. The suspect is what `ParseTypeKindInner` does
with the stripped name in its ARRAY arm.

**Do not "fix" it by making the array lookup owner-scoped.** `ArrType*` carries
no owner column at all (nor does `EnumType*`), which is precisely why the
qualified CAST had to answer those two kinds unscoped — see
`ClassDeclaresTypeNamed`'s header and
`bug-p-a-nested-type-can-be-declared-through-a-qualifier-but-not-cast-through-one`.
Adding the column is a separate change and would want both tables at once.
