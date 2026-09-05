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

## A NEARBY defect that is measurably NOT this one, found 2026-09-05 (frankC)

`sizeof` of an ARRAY TYPEDEF's NAME drops the dimension. Measured at
`9048792b2dc3`, and ablated against `10492cae86d8` — identical, so not a
regression from that day's pointer-to-typedef'd-array work, which found it.

```c
typedef double TA[4];   sizeof(TA)   gcc 32   pxx 8
typedef char   TC[4];   sizeof(TC)   gcc  4   pxx 1
typedef int    TI[4];   sizeof(TI)   gcc 16   pxx 4
```

**Filed separately as
[[bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size]], and the
reason it is not folded into this ticket is worth recording**, because the
first reading said it WAS this ticket. `sizeof(TA)` = 8 looks exactly like
`TypeSlotSize(tyUnknown)`, which is this ticket's whole complaint — and the
double row alone cannot tell the two apart, because `sizeof(double)` is 8 and
the pointer default is 8. The `char` and `int` rows separate them in one
command: a tyUnknown default answers 8 for all three, and the observed answers
are 8 / 1 / 4, i.e. the ELEMENT size every time. Different mechanism, so a
fixer who came here from that number would have been sent to the wrong walk.

Recorded here rather than only in the new ticket so the next person who
measures `sizeof(TA)` = 8 and recognises this ticket's signature has the
discriminator in front of them.

## 2026-09-05 (frankC): the nearby defect is CLOSED, and it was not this one

[[bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size]] is fixed, and
it was the visible edge of a memory-corruption bug — `CTypedefArrLen` held only
the FIRST dimension, so `typedef int T2[2][3]` was allocated for 2 elements and
indexed with a 2-wide row. Different mechanism from this ticket, exactly as the
discriminator above said.

**The discriminator earned its keep.** `sizeof(TA)` = 8 for the `double`
typedef is indistinguishable from this ticket's `TypeSlotSize(tyUnknown)` = 8,
and the first reading did send it here. The `char` and `int` rows separated
them in one command. That is now pinned in `test/c_array_typedef_dims.c` rows
1-3, with a comment saying not to reduce them to one — **anyone who trims those
three rows to the `double` case reopens the confusion**, and this ticket is who
it costs.

**This ticket's own first job is still undone**: the census of which operands
actually reach `tyUnknown` here, and whether any real program spells one. Per
its own text, if the answer is none this is `rejected/` rather than a low prio.
Nothing in the array-typedef work touched that walk.
