---
track: N
prio: 40
type: bug
blocked-by: []
summary: "pylib treats VT_CHAR and VT_STRING as ONE string type in ordering, repr, concat and text extraction — but `PyVarEq` bails on `p^.VType <> q^.VType` before it ever gets there, and `PyVarHashKey` has no VT_CHAR arm either. So a char-tagged key stores fine and then misses every lookup. No NilPy-reachable repro today (the pystr_ofchar boundary converts at every crossing), but this is the mechanism that turned Counter(str) into a SILENT 0 instead of a loud KeyError."
status: backlog
owner: —
---

# A char key and a string key are equal everywhere except inside a dict

Split out of
[[bug-n-from-collections-import-counter-binds-something-that-always-answers-zero]],
which is fixed. That ticket's defect was one pylib site storing a raw Pascal
`s[i]`. This one is why that mistake was **silent** rather than loud, and it is
a different mechanism, so it is filed rather than folded in.

## The asymmetry

`compiler/builtin/pylib.pas` normalises `VT_CHAR` (5) and `VT_STRING` (6) into
one Python `str` at every site that asks "is this text?":

| site | treats 5 and 6 as one |
| --- | --- |
| `PyOrdCheck` | yes — `sa := (VType = 5) or (VType = 6)` |
| `pyvar_gt` | yes |
| `PyVarText` | yes — decodes both |
| variant concat (~8432), repr (~8825) | yes |
| **`PyVarEq`** | **no** — `if p^.VType <> q^.VType then Exit` |
| **`PyVarHashKey`** | **no** — arms for 6 and 8193, none for 5 |

So `pyvar_gt` will happily order a VT_CHAR against a VT_STRING as two strings,
while `PyVarEq` says they are not even the same value. `a < b` and `a == b`
disagree about what type `a` is.

`PyVarHashKey`'s own header states the invariant it exists to hold — *"equal
keys MUST hash equal"* — and lists the arms it added for exactly this reason
(int-family cross-tag, float-that-is-an-integer, tuple-by-content, all three
after a silent-key-loss bug). VT_CHAR is the arm that was never added, and the
two routines have to move together: fixing eq alone would put equal keys in
different buckets.

## Reachability — why this is prio 40 and not 80

Probed at `dev` (2026-08-26, self-hosted binary at the Counter fix): **no NilPy
user-level expression produces a VT_CHAR value.** `s[i]`, `for ch in s`,
`max(s)`, `min(s)`, `sorted(s)[0]`, `list(s)[0]`, `set(s)`, `chr(97)`,
`"a,b".split(",")[0]` — every one yields a VT_STRING and works as a dict key
against a string literal. pylib converts at the boundary with `pystr_ofchar`,
which `list(s)` (pylib.pas:7187) and `set(s)` (:7514) both call.

So there is nothing user-visible to repro today. What there is, is a **trap for
the next pylib author**: one forgotten `pystr_ofchar` produces entries that
store, print, sort, count in `len()` and appear in `items()` — and answer 0 or
"absent" to every lookup. That is precisely the failure the debugging playbook
opens with, and it cost this repo one ticket already.

## The fork

1. **Make eq/hash normalise**, matching the other six sites. Cheap, symmetric,
   and turns any future leak into a right answer. Cost: it *entrenches* VT_CHAR
   as a legitimate NilPy value rather than a Pascal implementation detail.
2. **Keep them strict and make the leak LOUD** — e.g. refuse a VT_CHAR key in
   `PyVarHashKey` the way it already refuses an unhashable object. A future
   forgotten conversion then dies at the store with a clear message instead of
   answering wrongly.

Option 2 is the better fit for the stated design (a NilPy value is never a
Char; pystr_ofchar is the one boundary), and it is the one that would have made
the Counter bug a five-minute fix. Option 1 is what the neighbouring sites
already do, so it is the less surprising change. **This is close enough to a
design call that whoever picks it up should read both and decide, or escalate
to Track U.**

## Where

- `compiler/builtin/pylib.pas` — `PyVarEq` (~5735, the `VType <> VType` bail at
  ~5793) and `PyVarHashKey` (~6238, the arm list).
- Test alongside `test/test_nilpy_counter_from_a_string.npy`, which is the
  existing witness for the symptom.

## Gate

Track N: `make compiler/pascal26` + the repro. Touching the dict hash is the
kind of change `tools/gate.sh quick` is worth running for.
