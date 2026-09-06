---
track: P
prio: 25
type: refactor
blocked-by: []
summary: "NodeArrNDInfo fills NDInfoNDims/Lo/Span but not the element triple — size, record id, type kind — so every caller that needs to know what an element IS re-derives it from Syms[] or RecField*, with its own AN_IDENT/AN_FIELD pair. That re-derivation is where three C bugs lived."
status: done
owner: frankB
---

# NodeArrNDInfo yields spans but not the element

- **Type:** refactor / capability gap — **NOT a bug.** No program behaves
  wrong; the function is correct for what it answers.
- **Found:** 2026-08-30 (frankC), same origin as
  [[refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array]].

The function resolves an array reference through three spellings (ident, field,
deref-of-pointer-to-array) and publishes `NDInfoNDims`, `NDInfoLo[]`,
`NDInfoSpan[]`. It stops one field short of what its callers need: the
**element** — `ElemType`/`ElemRecName` for an ident, `RecFieldType`/
`RecFieldRecId` for a field — and its size.

So each caller re-opens the spelling question it just had answered. Track C's
`CNodeArrayShape` is literally that: a wrapper whose whole body is the second
IDENT/FIELD switch, run again, to get the triple. Three shipped C bugs
(`bug-c-a-struct-field-partial-index-uses-the-outer-row-stride`,
`bug-c-a-multidim-array-field-decays-with-the-element-stride`,
`bug-c-sizeof-a-partial-index-answers-the-element-not-the-row`) were all a
missing FIELD half of exactly that second switch.

## Fix sketch

Publish `NDInfoElemTk` / `NDInfoElemRec` / `NDInfoElemSize` alongside the
spans, set in each of the three arms where the symbol is already in hand. Then
`CNodeArrayShape` collapses to the call plus its dynamic-array rejection, and
no caller has a reason to write the pair again.

Note the deref arm has no obvious element for a pointer-to-array of records;
leave `REC_NONE`/0 rather than inventing one, and let callers test.

## Gate

`make compiler/pascal26`; additive fields, so existing callers are unaffected
by construction — which is the claim to check, not to state.

## Premise holds verbatim at HEAD (frankS, 2026-09-05, Track P structural pass)

`NodeArrNDInfo` (`compiler/pasparser_call.inc:619`) fills `NDInfoNDims`,
`NDInfoLo[d]` and `NDInfoSpan[d]` on both its arms, and nothing else. There is
no element size, no record id and no type kind in either arm. Not stale.

Same caveat as its sibling: this is a structural claim, settled by reading the
function, and a behavioural probe cannot fail on it.

## Resolution (2026-09-06)

`NDInfoElemTk`, `NDInfoElemRec` and `NDInfoElemSize` are published beside the
spans, filled in **all four** arms — the ident and field arms of
`NodeArrNDInfo`, and both halves of `DerefPtrArrayNDInfo` (the pointer SYMBOL
and the pointee's ArrType row). The fix sketch said three arms; the deref one
is two.

**Cleared at the top of `DerefPtrArrayNDInfo`, not at each arm's exit.**
`NodeArrNDInfo` asks that arm FIRST and falls through to its own two when it
declines, so a False return must leave no stale element behind either — a
reader that trusted a leftover `NDInfoElemSize` from a previous node would get
a plausible wrong stride, which is the failure mode this family keeps producing.

**`NDInfoElemSize` is 0 when unknown and the zero is load-bearing.** The
natural thing to write is `TypeStorageSize(tyUnknown, REC_NONE)`, which is
**4** — the same 4 as `sizeof(LongInt)` — so a caller could not tell a real
answer from a blank one. That is CLAUDE.md's "choose a probe whose right answer
differs from the default", applied to the column rather than to a test row.

### The payoff is taken, not just made available

`NDRowSourceInfo`'s own second switch is **deleted** — it re-opened the
ident/field/deref question one line after `NodeArrNDInfo` had answered it, and
now reads `NDInfoElemTk`/`NDInfoElemRec` directly. **The remaining test is on
`tyUnknown` and not on the node kind**, which is the point: a node shape this
function has never heard of cannot reach it at all (the caller returned True,
so one arm matched), and a future arm that resolves an array without being able
to name its element says so in the column instead of falling into an `else`
nobody updated. Three locals went with the switch.

Track C's `CNodeArrayShape` is the other named beneficiary and is **not**
touched here — it is `cparser.inc`, and the topic belongs to whoever holds
[[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]]. The
columns it needs now exist.

### The frozen-string capacity is deliberately NOT a fourth column

Two arms can fill it (`SymPtrElemStrCap`, `ArrTypeElemStrCap`) and two cannot:
a plain array symbol and a record array field record their OWN cap (`SymStrCap`,
`RecFieldStrCap`) and **no column anywhere holds their ELEMENT's**. A column
two arms fill and two leave at zero is a partially-consulted record — the shape
an absence-hunting grep cannot find, because every reader compiles and the two
filled arms make the two blank ones look like arrays of plain strings. Written
into the declaration with the two missing columns named, so the next person
adds those first rather than the column.

### Gate

`test/test_a_partial_nd_row_reaches_a_copying_parameter_through_every_base_spelling.pas`
— 8 rows, `test-core`, byte-identical to fpc 3.2.2: a partial N-D row into a
COPYING parameter through the ident, field and deref base spellings, each with
a scalar and a RECORD element.

**The ablation is recorded in the file because half of it is bad news.**
Setting the field arm's `NDInfoElemTk` to `tyUnknown` and rebuilding breaks
row 3, so that column is genuinely guarded. Setting the field arm's
`NDInfoElemRec` to `REC_NONE` and rebuilding changes **nothing on any row,
including the record-element ones** — so the file does not cover
`NDInfoElemRec` and says so, rather than letting a reader infer coverage from
the presence of records. Whether the consumer does not need the record id on
this path or something downstream compensates for a missing one is not
established and is not that file's question.

### Not done here

The rank-1 half, [[refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array]],
is a separate landing on purpose: this one is additive and that one widens a
predicate every existing caller reads, including one in `cparser.inc` whose
correctness comment cites the `>= 2` restriction by name. Two commits so a
bisect can tell them apart.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
