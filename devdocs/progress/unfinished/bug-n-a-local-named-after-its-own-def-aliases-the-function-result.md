---
prio: 60
track: N
type: bug
blocked-by: []
summary: "A NilPy local whose name equals its enclosing def's name aliases the function result instead of being an ordinary local: `def mode(label): tonic, mode = label.split(' '); return tonic, mode` returns ('C', None) where CPython returns ('C', 'minor'). Silent wrong value, no diagnostic."
status: unfinished
owner: frankwasm
---

# A local named after its own def aliases the function result

- **Type:** bug — Track N. Silent wrong value, no diagnostic anywhere.
  Filed 2026-08-30 by frankwasm, found while minimising
  [[bug-n-a-later-wall-in-key-analysis-blocks-convertrawtext-and-songformatter]].

## Repro

```python
# mod.py
def mode(label):
    tonic, mode = label.split(" ")
    return tonic, mode
```

```python
from mod import mode
print(mode("C minor"))
```

| | output |
| --- | --- |
| CPython | `('C', 'minor')` |
| pxx | `('C', None)` |

The local `mode` is never bound. Same shape with `label`:
`def label(label: str): ...` raises
`AttributeError: 'NoneType' object has no attribute 'split'` at run time —
the *parameter* is gone too.

## Why

In Pascal, assigning to a function's own name assigns its **result**. NilPy
inherits that resolution, so a Python local that happens to share the def's
name is not a local at all — it lands on the result slot.

This is a known family with a fixed sibling. `compiler/pyparser.inc` already
guards the case where the local is spelled `result`:

```pascal
    { NOT literally 'Result': Pascal's implicit result variable is case-insensitive,
      and `for result in detector_results:` is ordinary Python (songformatter's
      key_analysis writes it). Spelled that way, the loop variable RESOLVED to the
      function's result and the def returned the last element instead of what it
      computed. `return` targets RetSymIdx by index, never by name, so a name no
      Python source can spell keeps the two apart.
      See bug-nilpy-local-named-result-aliases-the-function-result. }
    idx := AllocVar('$pyresult', retType);
```

The `$pyresult` rename fixed the `result` spelling. **The def's own name is the
unfixed arm of the same defect** — and it is the more likely one in real code,
because nobody writes `result = ...` inside a function called `result`, while
`mode`, `label`, `value`, `item` are ordinary local names that a small helper
is also plausibly named after.

Related but distinct: [[bug-bare-function-name-call-vs-resultvar]] (done) is
the Pascal-side reading of a bare function name in an expression. This one is
about NilPy **assignment** to a name that is supposed to be a local.

## Why prio 60 and not lower

It is the silent-wrong-behaviour class from CLAUDE.md's compat table: real
Python that CPython accepts and runs, compiled without a diagnostic, producing
`None` where a value belongs. It needs no unusual construct — one small helper
whose name matches a local it computes.

## What a fix must assert

- a local matching the def name, plain assignment
- the same via tuple unpacking (the repro above — `mode` is one target of two,
  and the *other* target binds correctly, which is what makes it hard to spot)
- a **parameter** matching the def name (`def label(label)`), which currently
  loses the parameter
- a loop variable matching the def name (`for mode in ...` inside `def mode`)
- the existing `result` spelling, which must stay fixed

---

## ROOT-CAUSED and PARKED, 2026-08-30 (frankwasm)

Parked in `unfinished/` **only** because the fix is one line in a file this
lane does not own. The diagnosis is complete and the patch is written out
below; the next holder starts at the edit, not at the repro.

### Correction: it is the READ side, not the binding side

The "Why" section above says the local "lands on the result slot" and points at
the `$pyresult` precedent. **That is wrong, and the IR says so.** The local is
allocated and the store is correct — it is the *read* that goes elsewhere:

```
PXXDBG=a.ir:mode      def mode(label): mode = 5; return mode
  1: const_int ival=5
  2: store_sym a=477 [sym=mode]        <- the local, bound correctly
  3: load_sym  a=474 [sym=$pyresult]   <- the return reads the RESULT var
```

So `PyAssignTargetSym` and the local-allocation loops are all fine, and a patch
there changes nothing — I wrote one and measured no effect before looking at
the IR. `PXXDBG=n.locals` printing `mode mode tk=13 | sym=<none>` is what sent
me the wrong way: that dump resolves through `PyProgSym` at a point where the
def's frame is no longer in scope, so `<none>` there does not mean unallocated.
**Worth knowing before trusting that field.**

### The site

`compiler/pasparser_expr.inc:7547` — FPC's `FuncName` synonym for `Result`, the
read side:

```pascal
      else if (CurProc >= 0) and Procs[CurProc].IsFunc and
              (Tokens[TokPos].Kind <> tkLParen) and
              not DelphiMode and
              ((name = Procs[CurProc].Name) or
               CaseEqual(name, LastDotName(Procs[CurProc].Name))) then
```

It already carries the precedent for the fix: `not DelphiMode`, because in
Delphi a bare own-name read is never the result var. **NilPy needs exactly the
same exclusion, for a stronger reason** — Python has no such rule at all, and
NilPy does not need one, because `return` targets `RetSymIdx` by index rather
than by name. That is the same reasoning that made the result slot `$pyresult`,
a name no Python source can spell; the own-name arm is the door that was left
open beside it.

### The patch

```pascal
              not DelphiMode and not isNilPy and
```

Recursion is unaffected: a following `(` is excluded by the guard above and
falls through to the call path. Verified: `def mode(label): ... return
mode(label[1:])` recurses correctly today and does not go through this branch.

### Why this lane did not apply it

`pasparser_expr.inc` is Pascal-frontend ground shared with Track A, and the
coordinator reported it held by **frankA** on 2026-08-30. The grant this lane
did hold was for `pasparser_lval.inc`, a different file — and that one turned
out not to be needed either (see the sibling ticket). Hand to whoever holds
`pasparser_expr.inc`; gate is Track A's (`gate.sh quick` + the fixedpoint),
because the branch is shared by every frontend that reads a bare own name.

### The four arms in the ticket, re-measured on `e632e0d82ef9`

| arm | now | want |
| --- | --- | --- |
| `mode = 5; return mode` | `None` | `5` |
| `tonic, mode = label.split(" "); return tonic, mode` | `('C', None)` | `('C', 'minor')` |
| `for mode in [...]: ...; return mode` | `None` | `'c'` |
| `def mode(...): return mode(...)` recursion | correct | must stay correct |
