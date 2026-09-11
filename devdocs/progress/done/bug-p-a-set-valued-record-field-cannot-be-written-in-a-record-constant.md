---
track: P
prio: 55
type: bug
owner: frankS
blocked-by: []
summary: "FIXED 2026-09-11: a SET-VALUED RECORD FIELD in a record constant — `(special:true; keyword:[m_none])`, how FPC's own tokens.pas writes its ~400-row token table — was refused with `expected field name in record constant` POINTING AT THE `[`. ConstEval cannot evaluate a set and does not CONSUME one either, so the field loop came back round with TokPos still on the value; the field name was never the problem. TryParseInitValForm exists to prevent exactly that message and the set arm was the one value form written out by hand in the const-ARRAY element loop and given to no other caller. Moved into the helper (kind 9 / AN_SET_CONST_REF over BakeSetConst) and the hand-written copy deleted; the var-initialiser slot, which failed with a DIFFERENT message and read as a separate bug, was fixed by the same move. Found by attempt 7 of umbrella-pxx-compiles-fpc-itself: 10 units stopped here."
status: done
---

# A set-valued record field cannot be written in a record constant

```pascal
arraytokeninfo : ttokenarray = (
    (str:''  ;special:true ;keyword:[m_none];op:NOTOKEN),
```

That is FPC's `compiler/tokens.pas`, ~400 rows of it, and it was refused with

```
expected field name in record constant
  near: special : true ; keyword : >>> [ m_none ]
```

**The message is about the wrong thing, and the file it came from says so.**
`TryParseInitValForm`'s own header paragraph:

> ConstEval cannot evaluate any of these — and, crucially, does not CONSUME them
> either, so letting one reach ParseInitValTk desyncs the field loop and the next
> iteration reports `expected field name in record constant` pointing at the
> value rather than at the real gap (that misleading message is what this exists
> to prevent).

## THE GAP WAS NEVER "SETS DO NOT WORK" — IT WAS WHICH SLOT

A const **array** of sets has worked since
[[bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements]], and that
ticket's fix is the reason this one exists: the arm was written out **inside the
const-array element loop**, so exactly one caller had it. Three slots did not:

| slot | before |
| --- | --- |
| set field in a const array of records | `expected field name in record constant` |
| set field in a scalar record constant | same |
| `var v: TSet = [x]` | `expected 'begin' before '['` — a THIRD message |

The var slot failing differently is why it reads as a separate bug and is not
one. One helper, three slots, one fix.

## The fix

`TryParseInitValForm` gains the set arm — kind 9 (`AN_SET_CONST_REF`) over
`BakeSetConst`, which already folds `[a,b]`, `[]`, `A + [x]` and a named set
constant into a 32-byte mask in `Data[]`, and which both flushes already rebuild
from that offset. **Nothing below the parser is new.** The hand-written copy in
the array loop is deleted, with a pointer left in its place.

`BakeSetConst` lives in `pasparser_decl.inc`, which is included AFTER
`pasparser_expr.inc`, so `forwards.inc` gains its forward — pxx prescans headers
and would not need it; the FPC seed does, and `gate.sh quick`'s FPC-seed canary
is what would have caught the omission.

## Two things measured rather than assumed

- **fpc 3.2.2 REFUSES a named set constant in either slot.** `keyword: both`
  inside a record constant and `var v: TSet = both` both answer `Illegal
  expression`. pxx accepts both, which CLAUDE.md classes as not a defect — so
  the ident arm exists and can never have a differential row. The fixture says
  so rather than asserting it.
- **The empty set cannot carry the test alone.** `[]` is what most rows of a
  token table hold, and it is also what a slot nothing ever wrote reads as. The
  fixture's `miss` row asserts a NON-empty neighbouring row in the same array,
  so "the bake did nothing" fails it.

## Test

`test/test_p_a_set_valued_record_field_in_a_record_constant.pas`, wired into the
Makefile. Positive control, verified: the PINNED compiler refuses the file at the
first table row with the original message. Every expected line is fpc 3.2.2's for
the identical source.

## Corpus effect

Attempt 7 of [[umbrella-pxx-compiles-fpc-itself]] reported 10 of 207 units
stopping here. **That is a queue position, not a size** — FPC's `tokens.pas`
does now compile under pxx, which is the claim that is actually measured.
