---
slug: bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown
track: C
prio: 40
type: bug
status: new
owner: ""
blocked-by: []
summary: "CSizeofDescriptorWalk can finish with cOK=True and cTk=tyUnknown, and then answers `sz := TypeSlotSize(tyUnknown)` = 8 -- a size it never established, wearing the pointer default so it is indistinguishable from a correct answer for a pointer operand. Because it also consumed the whole operand, CurTok sits on `)` and ParseCSizeof's general-expression fallback is excluded by its `CurTok.Kind <> tkRParen` guard, so the confident wrong answer is final. This is the exact shape fde15c1d1 already removed once (an arm that consumed part of an operand, failed, and left the default); the pointer-DEPTH fix closed the case that reached it via pointer-to-pointer subscripts, not the shape. NOT a free fix: making the walk decline sends the operand to the general path, whose own unknown-type branch is `else sz := 4`, so a genuinely untypable POINTER operand would move 8 -> 4, wrong in the other direction. Needs the fallback and the walk to agree on what 'I do not know' costs before either may decline."
---

# The sizeof descriptor walk answers from `tyUnknown`

Found 2026-09-02 while fixing
[[bug-c-sizeof-reaches-a-pointee-through-one-spelling-only]]; that ticket's own
defect was one route into this shape, and closing it did not close the shape.

## The shape

`CSizeofDescriptorWalk` ends with:

```pascal
else if cTk = tyRecord then sz := RecSize(cRec)
else sz := TypeSlotSize(cTk);      { cTk may be tyUnknown -> 8 }
...
Result := cOK;                     { True }
```

`cTk` reaches `tyUnknown` whenever a peel or a `.` lands on something whose
type was never recorded — a pointer with no pointee, a field whose
`RecFieldType` answers unknown. The walk then reports success and a size.

**A guard that cannot fail prints PASS.** This one prints 8, which is the
correct answer for every pointer operand, so the population where it is wrong
is invisible next to the population where it is right.

The caller compounds it: an arm that consumed the operand entirely leaves
`CurTok` on `)`, and the general-expression fallback is gated on
`CurTok.Kind <> tkRParen`. The comment there reasons that such an arm
"succeeded" — true when it was written, and this is the counterexample.

## Why declining is not a one-line change

Send the operand to the general path and its unknown branch is `else sz := 4`.
So an operand that neither path can type moves **8 -> 4**: still wrong, and now
wrong for the plain-pointer case that 8 got right by construction. The two
paths disagree about what "I do not know" costs, and that disagreement has to
be settled before either is allowed to decline. Whoever takes this should
decide the unknown-type answer ONCE and have both read it.

## What is established

- The general expression path types these operands correctly today:
  `sizeof((p2[0])[0])` = 40 against `sizeof(p2[0][0])` = 8, before the depth
  fix, on the identical operand.
- The depth fix (`SymPtrDepth`/`SymPtrBaseTk`/`SymPtrBaseRec` in the walk)
  removes the pointer-to-pointer route to `tyUnknown` and nothing else.
- Not measured: which other operands still reach `tyUnknown` here, and whether
  any real program spells one. **That census is the first job** — if the
  answer is none, this is `rejected/` rather than a low prio, per CLAUDE.md.
