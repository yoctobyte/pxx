---
prio: 55
track: N
type: bug
blocked-by: []
summary: "`def p(x: str): return x.partition(' ')` prints raw memory instead of ('C', ' ', 'minor'). The same call outside a def is correct, and split/rsplit through the same def-return path are correct. Pre-existing — reproduces on pinned."
status: new
owner: ""
---

# A tuple-returning str method prints raw memory when returned from a def

- **Type:** bug — Track N. Silent wrong value: not a crash, no diagnostic, a
  page of memory where a tuple belongs. Filed 2026-08-30 by frankwasm while
  adding the class-return rows to
  `test/test_nilpy_str_method_return_type_on_a_variable.npy`.

## Repro

```python
def p(x: str):
    return x.partition(" ")
print(p("C minor"))                # raw memory
print("C minor".partition(" "))    # ('C', ' ', 'minor')   <- correct
```

CPython prints `('C', ' ', 'minor')` for both.

## Pre-existing, measured

| compiler | `p("C minor")` |
| --- | --- |
| `pinned` | raw memory |
| HEAD + the scalar gate on the str-method-return arm | raw memory |

So it is **not** the arm
[[regression-test-nilpy-test-nilpy-startswith-tuple]] added, and not the gate
that arm just grew. Both were checked, because from outside the shapes are
identical.

## Why its own ticket and not a row on that one

`split` / `rsplit` — the **list**-returning rows of the same family — are
correct through the same def-return path, and are now asserted in that test.
So the path keeps a list's class identity and loses a tuple's. One concept,
two mechanisms, one broken: the smell `devdocs/dev/root-cause-over-microfix.md`
names. Start by asking why the list arm carries its `ci` and the tuple arm does
not — do not patch `partition`.

## Where it is NOT

Outside a def the same expression is correct, and so is binding it to a local
first, so the lowering and the tuple itself are fine. It is the def's inferred
RESULT type.

Note for whoever picks this up: `PXXDBG=n.locals` printing `sym=<none>` is NOT
evidence that a local was never allocated — that dump resolves through
`PyProgSym` at a point where the def's frame is out of scope. `PXXDBG=a.ir:<proc>`
is the probe that answers this one; it is what separated the store from the
load in the sibling ticket
[[bug-n-a-local-named-after-its-own-def-aliases-the-function-result]].

## What a fix must assert

- `partition` and `rpartition` returned directly from a def
- the same via a local first (`t = x.partition(" "); return t`)
- `split` / `rsplit` must stay correct — the working arm, and the regression risk
- the same call outside a def, which must stay correct
