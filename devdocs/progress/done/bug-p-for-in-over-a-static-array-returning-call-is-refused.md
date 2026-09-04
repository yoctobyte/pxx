---
slug: bug-p-for-in-over-a-static-array-returning-call-is-refused
title: "`for x in MkArr` — a function returning a STATIC array — is refused; the dyn-array twin works"
track: P
prio: 35
type: bug
status: done
found: 2026-09-04
found-by: frankA
owner: ""
blocked-by: []
summary: "`for x in MkArr do` where MkArr returns array[0..3] of Integer is refused, and the method spelling `for x in o.GetArr do` is refused with a different message. The DYNAMIC-array twin of both works and has since compat-pascal-index-a-function-call-result. Split out of the p^ for-in fix rather than merged into it: the pointer-deref shape reads its extent from the pointer symbol's SymPtrElem* columns and a call result reads it from ProcRetFixedArrBytes/RetType, which is a real difference in shape SOURCE, not a spelling."
---

# for-in over a call returning a static array

Split out of [[bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused]]
while tabulating for-in container shapes — that ticket named only `p^`, and the
table found three failing rows.

## Measured — binary `f8b9e4394673`, oracle fpc 3.2.2, after the `p^` fix landed

| container | pxx | fpc |
| --- | --- | --- |
| `aa` bare static var | ok | ok |
| `pa^` deref to static array | ok (fixed in `d9604ea59`) | ok |
| `dd` bare dyn var | ok | ok |
| `rr.arr` record field | ok | ok |
| `oo.fArr` class field | ok | ok |
| `MkArr` **function → static array** | `for-in: not a generator, enum type, or iterable variable` | `0 10 20 30` |
| `oo.GetArr` **method → static array** | `for-in: unsupported iterable expression` | `0 10 20 30` |

**Two messages, one gap** — the bare spelling dies at the container-expression
dispatch and the qualified one gets as far as `ParseForInNodeAST`. That split is
the same one the `p^` ticket turned on and is worth knowing before reducing.

## The shape of the fix, and why it was not done under the `p^` ticket

`ParseForInNodeAST` already has the dyn-array arm for precisely this case — *"a
dynamic-array VALUE that is not a bare variable: a function result ... every
array path below keys on a SYMBOL, which such a node has not got"* — and
materialises into a hidden dyn-array local, per
`compat-pascal-index-a-function-call-result`.

A static array needs the same move with two differences that are real:

1. **The extent comes from somewhere else.** `ProcRetFixedArrBytes[procIdx]` and
   `Procs[].RetType`, not `SymPtrElemArrLen` / `DerefPtrArrayInfo`. The `p^` fix
   uses the latter; sharing one arm would mean one of the two asking a question
   it cannot answer.
2. **Materialising is correct here and was NOT correct for `p^`.** A call result
   is a temporary with no aliasing obligation, so copying it into a hidden local
   is exactly right — whereas copying a pointer's static pointee diverges from
   FPC the moment the body writes through the pointer. The `p^` fix therefore
   indexes the node in place, and this one should not copy that decision.

`ApplyCallResultPtrSuffix` already materialises a fixed-array call result for
the INDEX spelling, so the machinery exists — **but that function is frankH's
ground as of 2026-09-04; coordinate before entering it.**

## Gate

The seven-row table above against fpc 3.2.2, plus a side-effect row (the
container must be evaluated exactly ONCE — a function that increments a counter
and is iterated must leave the counter at 1, which is both FPC's behaviour and
what the dyn-array arm already promises).

---

## 2026-09-04 (frankA) — FIXED, both spellings, through ONE predicate

### The two messages were one gap

The summary notes the two spellings refused *"with a different message"*, and
that is exactly why it read as two problems. It is one:

- `for x in MkArr` died at the container-**expression dispatch** in
  `ParseStatementAST` — *"for-in: not a generator, enum type, or iterable
  variable"* — and never reached `ParseForInNodeAST` at all.
- `for x in o.GetArr` got as far as `ParseForInNodeAST` and died there —
  *"unsupported iterable expression"*.

Two sites, each with its own idea of what is iterable, and neither knew about a
fixed-array call result. Both now ask **one** predicate,
`NodeIsFixedArrayCallResult`, so they cannot drift apart again. That is the
`44c08dc66` / `PasNodeProcSig` shape frankH established next door: one
**node-keyed** answer rather than a per-spelling one, and the predicate answers
for all four call kinds (`AN_CALL`, `AN_VIRTUAL_CALL`, `AN_CLASS_VIRTUAL_CALL`,
`AN_INTF_CALL`), not the two the failing spellings happened to use.

### Materialising is correct HERE and was wrong for the sibling

The arm assigns the result into a hidden local and iterates that. The sibling
ticket [[bug-p-for-in-over-a-deref-ignores-a-non-zero-low-bound]] indexes **in
place** and its test has a row (`aliased=139`) that fails if you copy. Both are
right:

- a **call result** is a temporary nobody else holds, so a private copy aliases
  nothing — and copying is what makes single evaluation observable;
- a **pointee** is live storage the loop body can write through, so a copy
  changes the answer.

Same question, two answers, decided by the shape. Worth writing down because
the natural instinct after fixing one is to make the other match.

### Measured, against fpc 3.2.2

`.expected` IS FPC's own output on the test source; `diff` is empty.

```
bare=1 2 3 4        calls=1
method=5 6 7 8
lowbound=20 30 40   (array[2..4] — a result whose type does not start at 0)
recelem=7 8 9       (array of RECORD, so the element is not a scalar)
```

**`calls=1` is the load-bearing row.** It is the thing materialising has to
buy, and a re-evaluating loop prints `4`. A value-only check on the other three
rows passes either way — every element would still be right — so without this
row the test would certify a loop that calls the function once per iteration as
correct. `lowbound=` is the second one that can actually fail: the extent path
would read a length where it needs a bound.

### Positive control

`stable_linux_amd64/default/pinned` on the same source:
`pascal26:52: error: for-in: not a generator, enum type, or iterable variable`.
The test fails on the pre-change binary.

Test: `test/test_forin_static_array_call.pas` (+`.expected`), wired in the
Makefile beside the deref rows. `python3 tools/check_test_wiring.py` with no
arguments reports it wired — **not** the gate's `this push wires the tests it
adds` row, which is scoped to `origin/master..HEAD` and passes on zero rows
when you gate before committing, as CLAUDE.md tells you to. (Thanks to frankH
for that one; it caught none of their four either.)

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
