---
slug: bug-p-a-char-array-row-of-a-2d-array-is-not-a-string
track: P
type: bug
prio: 25
status: backlog
found: 2026-09-02
found-by: frankZ
owner: ""
blocked-by: []
summary: "`a[0] := 'hi'` where `a: array[0..2] of array[0..15] of Char` is still refused as `cannot assign ShortString to Char`. ASTCharArrayCap now answers for AN_IDENT, AN_FIELD and AN_DEREF, which is every shape the synapse failure and its five siblings needed; the AN_INDEX row of a multi-dimensional Char array is the one left, and it needs a per-dimension extent the other three do not. Low prio on purpose: no measured program wants it — it is the residual named when the parent bug closed, not a report from real code."
---

# A Char-array ROW of a 2-D array is not a string

Residual of [[bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string]],
named at close rather than found separately. **Nothing measured wants this** —
it is here so the exculpation has an owner, not because a program hit it.

## The one shape still refused

```pascal
var a: array[0..2] of array[0..15] of Char;
begin
  a[0] := 'hi';        { error: incompatible types: cannot assign ShortString to Char }
end.
```

Six of seven lvalue shapes work as of the parent fix (plain variable, record
field, nested field, a field of a record array element, pointer deref, and the
read direction of each). This is the seventh.

## Why it was left out rather than forgotten

`ASTCharArrayCap` answers "the element count if this node denotes a STATIC Char
array". For the three shapes it now handles, the extent is a single recorded
number — `Syms[].ArrLen`, `RecFieldArrLen`, `DerefPtrArrayInfo`'s flatCount.
For an AN_INDEX row it is not: the capacity of `a[0]` is the INNER dimension's
span, and the node's own tag carries neither. Getting it right means resolving
the base's dimension table and asking for span `d=1`, which is a different
derivation from the other three and would want its own measurement — including
the `array[0..2, 0..15] of Char` spelling, which may or may not land in the
same node shape.

The parent fix deliberately returns -1 for every multi-dimensional case in all
three arms rather than guessing an extent, because a WRONG capacity here is a
buffer write past the row, and the current behaviour is a loud refusal.

## Do not confuse this with

`array[0..15] of Char` reached through an index — `ra[1].a := 'q'`, where the
INDEX is on the record and the field is the Char array — which works and is
asserted by `test/test_char_array_field_is_a_string.pas` (`elem-field`).
