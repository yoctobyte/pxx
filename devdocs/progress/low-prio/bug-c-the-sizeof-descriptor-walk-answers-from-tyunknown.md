---
slug: bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown
track: C
prio: 15
type: bug
status: low-prio
owner: ""
blocked-by: []
summary: "CENSUS DONE 2026-09-05 (frankC), which this ticket named as its first job: 10932 descriptor walks over 629 C test files plus lua 5.4 and the sqlite amalgamation, and exactly ONE reaches cTk=tyUnknown -- sqlite3.c:137935 `sizeof(wsdAutoext.aExt[0])`, where the field is `void (**aExt)(void)` so the pointer default of 8 is THE RIGHT ANSWER, confirmed against gcc. The shape is real and reachable by a real program; the one instance of it is correct by coincidence rather than by the walk knowing anything. NOT rejected/ (the answer is not none) and not worth doing now: the documented fix sends the operand to a fallback whose unknown branch is `else sz := 4`, so the only existing site would move from a right answer to a wrong one. Low-prio. A SECOND FINDING the census produced: cOK was False in ZERO of 10932 walks -- three sites set it and none fired -- so the decline path this ticket wants to use does not exist in practice yet, and whoever adds one is adding the first. Precondition unchanged: the walk and the fallback must agree on what \"I do not know\" costs before either may decline."
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

### AND THE DECLINE PATH HAS NEVER RUN — measured, not inferred

**`cOK` was False in ZERO of 10932 descriptor walks** across 629 C test files,
lua 5.4 and the sqlite amalgamation (census below). Three sites in the function
set `cOK := False`; **none of them fired.**

This section is written as though the job were REBALANCING an existing
mechanism. It is not. **Whoever adds a decline is adding the first one**, with

- no live caller that has ever exercised it,
- no evidence the caller's `CurTok.Kind <> tkRParen` exclusion — the thing this
  ticket blames for making the wrong answer final — behaves as assumed under a
  decline that actually happens, because one never has,
- and therefore no regression to measure against.

So the cost is **introduce, not adjust**, and the risk is not "might regress a
site" but "no site has ever run this". That is the sentence that stops the next
taker estimating this wrong, and it is why the precondition above is a real
precondition rather than a caution.

*(It is also, in miniature, this ticket's own subject: a guard that cannot fail
sitting inside the ticket about a guard that cannot fail.)*

## What is established

- The general expression path types these operands correctly today:
  `sizeof((p2[0])[0])` = 40 against `sizeof(p2[0][0])` = 8, before the depth
  fix, on the identical operand.
- The depth fix (`SymPtrDepth`/`SymPtrBaseTk`/`SymPtrBaseRec` in the walk)
  removes the pointer-to-pointer route to `tyUnknown` and nothing else.
- ~~Not measured: which other operands still reach `tyUnknown` here~~ —
  **DONE, see the census below.** One operand in the whole corpus reaches it
  (`sqlite3.c:137935`) and the default answers it correctly. Not none, so not
  `rejected/`; one and correct, so not worth doing.

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

# 2026-09-05 (frankC): THE CENSUS THIS TICKET NAMES AS ITS FIRST JOB IS DONE

The ticket says: *"Not measured: which other operands still reach `tyUnknown`
here, and whether any real program spells one. **That census is the first job**
— if the answer is none, this is `rejected/` rather than a low prio."*

**The answer is ONE, in sqlite, and it is correct.**

## Instrument

`CSizeofDescriptorWalk` instrumented at its single exit to report `cOK` and
`cTk` on EVERY completion — not only on the tyUnknown case. That is deliberate:
a probe that fires only on the shape you are hunting gives you a zero with no
denominator, and a zero is what a dead instrument returns. Reverted after the
run; the shipped compiler carries none of it (`strings | grep -c PXXCENSUS` = 0).

**The aperture was checked rather than assumed.** The function has no early
`Exit` — its only `Result :=` is the last statement and every `cOK := False`
path falls through to it — so "declined: 0" below is a fact about the whole
function and not about where the probe sits.

## Result

| | |
| --- | --- |
| C files tried | 629 |
| **reached the compiler** | **629** |
| lua 5.4 core, sqlite amalgamation | both, in full |
| **total descriptor walks** | **10932** |
| walks that DECLINED (`cOK` False) | **0** |
| walks reaching `cTk = tyUnknown` | **1** |

## The one site, named

`library_candidates/sqlite/sqlite3.c:137935`

```c
static SQLITE_WSD struct sqlite3AutoExtList {
  u32 nExt;
  void (**aExt)(void);      /* pointers to the extension init functions */
} sqlite3Autoext = { 0, 0 };
...
u64 nByte = (wsdAutoext.nExt+1)*sizeof(wsdAutoext.aExt[0]);
```

The walk answers **8** from `TypeSlotSize(tyUnknown)`. `aExt[0]` is a FUNCTION
POINTER, so 8 is **the right answer** — measured against gcc, which also says
8. The default is correct here for a reason the walk had nothing to do with.

**This is the ticket's own complaint, instantiated.** The one operand in the
corpus that reaches the unrecorded case is one where the unrecorded answer
happens to be right, so nothing observable is wrong today and nothing would
have surfaced it. Had that field been `double (*x)[4]` the same walk would have
answered 8 for a 32-byte object.

## What this changes about the ranking

Not `rejected/`: the answer is not "none", and a real program — the largest C
corpus we have — spells the shape. But the exposure is **one site, correct**,
and the fix is the one this ticket already documents as not free: making the
walk decline sends the operand to a fallback whose unknown branch is
`else sz := 4`, so a genuinely untypable POINTER operand moves 8 -> 4, wrong in
the other direction. Trading a right answer for a wrong one on the only site
that exists is not an improvement.

**Moved to `low-prio/`.** Real, correctly diagnosed, no plan to do it, no claim
it is wrong. The precondition for ever doing it is unchanged and is written
above the fold: **the walk and the fallback must agree on what "I do not know"
costs before either is allowed to decline.**

## A second finding the census produced, which the ticket did not predict

**`cOK` was False in zero of 10932 walks.** The function returns Boolean, three
sites set `cOK := False`, and none of them fired across the whole corpus. So
the caller's `CurTok.Kind <> tkRParen` exclusion — the thing this ticket
identifies as making the wrong answer final — is never reached by a decline
either. **A guard that cannot fail, in the ticket's own subject.** Worth
knowing before anyone adds a decline path: they will be adding the FIRST one,
not changing the balance of existing ones.
