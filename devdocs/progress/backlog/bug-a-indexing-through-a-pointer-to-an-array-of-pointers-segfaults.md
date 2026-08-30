---
slug: bug-a-indexing-through-a-pointer-to-an-array-of-pointers-segfaults
track: A
prio: 60
type: bug
status: backlog
owner:
blocked-by: []
summary: "`p^[i]` where p is a pointer to an array whose ELEMENT TYPE is pointer-kind (Pointer, PChar, PInteger) segfaults, on read AND write, in a plain default build. The identical code with an Integer or Int64 element type is correct, and FPC gets all of it right. It compiles clean and dies at run time, so it is a false green for any build-only check. This is the REAL blocker behind bug-b-tlist-has-no-list-property: adding FPC's `property List: PPointerList` to TList would compile and then segfault at the documented idiom `L.List^[i]`, so that ticket is blocked on this one rather than being an RTL gap."
---

# `p^[i]` segfaults when the array's element type is a pointer

## Measured

Binary `992065f21f33` (the pin). Plain default build, no define, no flag.
Same program, only the element type varying:

```pascal
type TA = array[0..3] of <ET>; PA = ^TA;
var a: TA; p: PA;
begin
  p := @a;
  p^[1] := Default(<ET>);      { WRITE -- read fails identically }
  WriteLn('ok');
end.
```

| element type | result |
| --- | --- |
| `Integer` | **works** |
| `Int64` | **works** |
| `Pointer` | **SEGFAULT** (rc=139) |
| `PChar` | **SEGFAULT** |
| `PInteger` | **SEGFAULT** |

So it is **pointer-KIND elements**, not `Pointer` the type name.

## Oracle

FPC gets the whole thing right. On the read side, four rows, FPC vs pxx:

```
                     FPC     pxx
1 direct   s[0]      100     100
2 (pl^)[0]           100     <segfault>
3 pl^[1]             101     -
4 pl^[2] := 999 ;    999     -
  then s[2]
```

pxx prints row 1 and dies on row 2. `fpc -Mobjfpc` on the identical source
prints all four.

## Not a pointer-to-array problem in general

Worth stating, because that is the obvious first guess and it is wrong:
`pointer-to-record` deref (`pr^.x`) is **correct**, and `pointer-to-array-of-Integer`
indexing (`pia^[1]`) is **correct**, in the same program that then dies on
`pointer-to-array-of-Pointer`. The dereference machinery works; something on the
pointer-element path does not.

## Why it matters more than it looks

`p^[i]` over an array of pointers is an ordinary Pascal idiom, not a corner:
it is how FPC's own `TList.List` is consumed, and fcl-xml writes
`TObject(FBindings.List^[I]).Free` at `xmlutils.pp:760`.

**It compiles clean and dies at run time**, so any check that builds without
running reports success. Found only because the program was run.

## Consequence for [[bug-b-tlist-has-no-list-property]]

That ticket asks for `property List: PPointerList read FList` on `TList`, and the
storage supports it — measured: `Pointer(a) = @a[0]` for a dynamic array and the
stride is 8, so the layout is exactly what `PPointerList` expects.

**Adding the property anyway would be wrong today.** It would compile, and then
segfault at the one idiom it exists to enable. That converts an honest
`"List": no such member` into a crash at a call site, which is strictly worse:
the current error names the problem at compile time. The property should land
**with or after** this fix, and that ticket is now `blocked-by` this one.

## Gate

`make compiler/pascal26` + the element-type table above, **run, not just built** —
every row compiles.
