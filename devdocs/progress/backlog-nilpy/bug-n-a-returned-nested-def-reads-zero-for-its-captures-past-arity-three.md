---
slug: bug-n-a-returned-nested-def-reads-zero-for-its-captures-past-arity-three
title: a returned nested def reads zero for its captures past arity three
summary: >
  A nested `def` taken as a value reads its captured variables as ZERO once it
  has four or more of its own parameters; a `lambda` with the same parameters
  and the same captures is correct. This is the same bridge as
  `bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one`, resolved
  2026-07-30 in aad020a59 — the boundary moved from "exactly 1" to "1..3" and
  stopped there, so the fix generalised the arity range without removing the
  cap. Two of that ticket's rows never came back at all: a STRING capture is
  wrong at EVERY arity, and a list capture past the cap silently yields `[]`.
  All of it is silent — the "make the bailout LOUD" half of the old ticket's
  plan is still not in, so these are plausible wrong values, not errors.
track: N
type: bug
prio: 60
owner: unassigned
status: open
---

## How it was reached

From lekkerzeilen, sideways. `app.py` carries per-step values into a callback
with the standard Python idiom — a defaulted parameter,
`lambda g, f, t, p, n=first: ...`. While that was broken (the overload-retry
bug, fixed in aa43f495a) I rewrote those as factory closures, which is the
other standard idiom:

```python
def _fill_step(self, stage, name, i, o, d):
    def step(g, f, t, p):
        return stage[name].fill(i, o, d[o:o + self.SLICE])
    return step
```

That produced `TypeError: object is not subscriptable`, because `d` arrived as
`0` and `o` as a stack address. Four parameters — `(g, f, t, p)` — is exactly
the demo's callback shape, so BOTH idioms for carrying a value into a
4-parameter callable were wrong at the same time. That is the practical cost
here: the two things a Python programmer reaches for first both fail, and
neither says so.

## Repro

One file, no imports, no package. Every row should print `i=False o=7`.

```python
def k3(i, o):
    def step(a, b, c):
        return "i=%s o=%s" % (i, o)
    return step


def k4(i, o):
    def step(a, b, c, e):
        return "i=%s o=%s" % (i, o)
    return step


def lam4(i, o):
    return lambda a, b, c, e: "i=%s o=%s" % (i, o)


print("k3   (nested def, 3 params) ->", k3(False, 7)(1, 2, 3))
print("k4   (nested def, 4 params) ->", k4(False, 7)(1, 2, 3, 4))
print("lam4 (lambda,     4 params) ->", lam4(False, 7)(1, 2, 3, 4))
```

```
k3   (nested def, 3 params) -> i=False o=7
k4   (nested def, 4 params) -> i=0 o=0        <-- wrong, silently
lam4 (lambda,     4 params) -> i=False o=7    <-- negative control
```

Measured at bccef26c7, compiler binary 2026-09-14 02:36, `--threadsafe`
x86-64. The lambda row is the control that says this is the nested-def
lowering and not the call ladder.

## The table, re-run from the closed ticket

`bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one` carried a
table; this is that table at HEAD, with the arity range extended. Each row
captures `n = 42` (or a str/list) and is RETURNED before being called.

| closure shape | CPython | pxx @ bccef26c7 |
| --- | --- | --- |
| `def b():` called INSIDE the parent | 42 | 42 |
| `def b():` returned, arity 0 | 42 | 42 |
| `def b(x):` arity 1 | 42 | 42 |
| `def b(x, y):` arity 2 | 42 | 42 |
| `def b(x, y, z):` arity 3 | 42 | 42 |
| `def b(x, y, z, w):` arity 4 | 42 | **0** |
| `def b(x, y, z, w, v):` arity 5 | 42 | **0** |
| str capture, arity 1 | `forty-two` | **0** |
| str capture, arity 4 | `forty-two` | **0** |
| list capture, arity 1 | `[4, 2]` | `[4, 2]` |
| list capture, arity 4 | `[4, 2]` | **`[]`** |

Three separate readings out of that:

1. **The arity cap moved, it did not go.** 0..3 now work where only 1 did.
   Whatever `PyNestedDefClosureValue` does with `nOwn` is now right for four
   values rather than one, and still has a ceiling.
2. **The string-capture bailout was never fixed.** The old ticket flagged it in
   its "Also note" — `tyAnsiString` / `tyString` captures bail outright — and it
   is still wrong at arity 1, which is the arity that ticket declared working.
   It now reads `0` rather than the `''` recorded then, so the fallback it lands
   in has changed even though the bail has not.
3. **A list capture past the cap gives an EMPTY LIST, not garbage.** `[]` is a
   perfectly plausible value for a caller to accept and carry on with, which
   makes it the most dangerous row in the table.

Also measured, for whoever picks this up: capturing `self` as well as two locals
in a 4-parameter nested def inside a METHOD does not read zeros, it SEGFAULTS
(rc=139). That is likely the same unbound-capture read landing on a pointer
field rather than an integer one, and it is a faster thing to debug than a
wrong number:

```python
class Holder:
    def make4_self(self, i, o):
        def step(a, b, c, e):
            return "i=%s o=%s tag=%s" % (i, o, self.tag)
        return step
```

## Where to look

The closed ticket names the machinery and it should still be the right place:
captures are lifted to trailing parameters appended by the call site
(`pyparser.inc` ~10350), and a def taken as a VALUE re-lowers through
`PyNestedDefClosureValue` (`pyparser.inc` ~4317) building a bound compiled
function via `pyboundfn_new` / `pyboundfn_bind`. That ticket's fix 2 —
"carry the own-argument count alongside `a0var` and have the bridge marshal
that many" — is the fix this needs, and the shape of the table says it was
done for a bounded number of own arguments rather than for any.

The neighbouring `bug-n-a-callable-attribute-dispatched-at-run-time-takes-at-most-4-arguments`
has a 4 in it too and is NOT this ticket: that one is a deliberate, loud refusal
out of the `pyvar_callv0..4` ladder. This one is silent and wrong. Whether the
two 4s share a root is worth one look and no more — the lambda control says
this is not the call path.

## The cheap half is still unlanded and still worth landing first

The closed ticket's fix 1 was "make the bailout LOUD": every `Exit` in
`PyNestedDefClosureValue` reached while there is something to bind is a
silently-wrong-program. Every row marked in bold above is that `Exit`. A
compile error naming the arity and this ticket would have turned all of them —
including the lekkerzeilen callback that started this — into a build failure
with a line number instead of a `TypeError` four frames away. It is the
project's stated preference and it is cheaper than the bridge work.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the whole
table above (arity 0..5; captures of int, str, list and a parameter; called
inside the parent and after escaping; the method-plus-`self` row), expectations
taken from CPython's own output. The lambda rows belong in the same fixture as
the negative control — they are what stops a future fix from being credited to
the wrong lowering.

## Log
- 2026-09-14 — filed from the lekkerzeilen startup investigation. Reduction and
  table measured by the lekkerzeilen seat; fixture files are single-file and
  inline above, so nothing outside this ticket is needed to reproduce.
