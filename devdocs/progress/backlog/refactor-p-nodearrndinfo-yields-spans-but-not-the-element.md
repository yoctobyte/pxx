---
track: P
prio: 25
type: refactor
blocked-by: []
summary: "NodeArrNDInfo fills NDInfoNDims/Lo/Span but not the element triple — size, record id, type kind — so every caller that needs to know what an element IS re-derives it from Syms[] or RecField*, with its own AN_IDENT/AN_FIELD pair. That re-derivation is where three C bugs lived."
status: backlog
owner: unassigned
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
