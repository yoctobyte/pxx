---
slug: bug-p-a-char-array-row-of-a-2d-array-is-not-a-string
track: P
type: bug
prio: 25
status: done
found: 2026-09-02
found-by: frankZ
owner: frankB
blocked-by: []
relates: [bug-p-a-char-array-row-through-a-pointer-deref-loads-short]
summary: "FIXED for a VARIABLE and a RECORD-FIELD base, in both directions and all three spellings (`array[0..2, 0..5]`, `array[0..2] of array[0..5]`, `array[0..2] of R`). ASTCharArrayCap grew a fourth arm that asks NDRowSourceInfo, the predicate ASTNDRowSubs already exists for, so no layout is re-derived. The reported store half was the loud half; the LOAD half was unreported and worse -- `s := a[0]` compiled, exited 0 and assigned ONE character where fpc assigns the row. A DEREF base is excluded and filed separately: it loads three characters of six, and admitting it would trade a wrong answer for a more plausible one."
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


# Resolved

## The ticket's own ranking was the thing that was wrong

`prio: 25`, and the body said *"nothing measured wants this -- it is here so the
exculpation has an owner, not because a program hit it."* Both true of the shape
that was reported. But the reported shape is the STORE, and the store is the arm
that FAILS LOUDLY. The load direction of the same predicate was never probed:

```pascal
var a: array[0..2, 0..3] of Char; s: ShortString;
...
s := a[1];        { 'x' -- one character. fpc gives 'xyz!'. exit 0. }
writeln(a[2]);    { the same, silently }
```

An AN_INDEX node's own `ASTTk` is the ELEMENT's kind, so a partial row read as
one Char everywhere, with no diagnostic. That is a wrong VALUE in real
compiling code, which the goal doc ranks as a bug outright, and it was sitting
under a prio that said nobody wants this. **The refusal is what got reported
because a refusal is what you can see** -- the same asymmetry the parent ticket
found between five refused lvalue shapes and one silently-unchecked one.

## The fix

`ASTCharArrayCap` grew a fourth arm. The extent is not a single recorded number
the way `Syms[].ArrLen`, `RecFieldArrLen` and `DerefPtrArrayInfo`'s flatCount
are -- which is the reason the parent fix left it out -- but it is not derived
here either: `NDRowSourceInfo` already answers *how many elements does this
partial index name, and of what*, and it walks IDENT, FIELD and DEREF bases. The
arm asks it. No fifth copy of the layout.

**Addressing needed nothing**, and that was measured rather than assumed:
`BuildPartialNDRowIndex` already scales the leading subscript to the row's
first-element flat index, so `@a[1]` was the row base at HEAD. What was missing
was only the ANSWER to the capacity question -- which is why both directions
broke at once, and only one of them loudly.

## Exactly one dimension must remain

`a[0]` on a 3-D array names a 2-D sub-array and fpc refuses a string there.
`NDRowSourceInfo` would return the PRODUCT of the trailing dimensions, which is
a plausible number and the wrong one: a capacity that spans rows is a write past
the row -- the risk the parent fix refused to guess at. `ASTNDRowSubs[node] =
NDInfoNDims - 1` separates them, and
`test_char_array_3d_row_not_a_string_fail.pas` is the only test that fails if it
is dropped, because every positive row is 2-D, where one subscript already IS
all-but-one.

## The DEREF base is excluded on purpose

Measured: `q^[1]` over `^array[0..2, 0..5] of Char` STORES correctly and LOADS
three characters of six, while `q^[0]` loads all six. At HEAD both loaded ONE.
Admitting it would trade a wrong answer for a MORE PLAUSIBLE wrong answer.
Filed with the measurement as
[[bug-p-a-char-array-row-through-a-pointer-deref-loads-short]].
