---
track: N
prio: 88
type: bug
blocked-by: []
summary: "A def with NO return annotation whose return expression is `/` infers an int return: `return x / 2` truncates to 2 for an unannotated param, and for `def b(x: int)` prints 4612811918334230528 — the float's raw bit pattern reinterpreted as an integer. Silent wrong values, no diagnostic."
status: working
owner: frank1-N-truediv
---

# Inferred return type of `/` is int — the float is truncated, or reinterpreted

- **Type:** bug (Track N — Nil Python frontend) — filed by Track D while
  verifying `docs/targets/nil-python.md` against the compiler
  ([[docs-verify-nil-python-page-against-the-compiler]]).
- **Found:** 2026-08-19 against pin **v363** (`stable_linux_amd64/default/pinned`).
- **Severity:** silent wrong value. Nothing is reported at compile time and the
  program runs to completion with a wrong number.

## Repro

```python
def a(x):
    return x / 2
def b(x: int):
    return x / 2
def c(x: float):
    return x / 2
def d(x: int) -> float:
    return x / 2
def e(x):
    r = x / 2
    return r
print(a(5)); print(b(5)); print(c(5.0)); print(d(5)); print(e(5))
```

| | pxx (v363) | CPython 3 |
| --- | --- | --- |
| `a(5)` — no annotations at all | **`2`** | `2.5` |
| `b(5)` — param annotated, return not | **`4612811918334230528`** | `2.5` |
| `c(5.0)` — param annotated float, return not | **`4612811918334230528`** | `2.5` |
| `d(5)` — return annotated `-> float` | `2.5` | `2.5` |
| `e(5)` — via a local, return not annotated | `2.5` | `2.5` |

`4612811918334230528` is `0x4004000000000000` — the IEEE-754 bit pattern of
`2.5` read as an Int64. So the value is computed correctly as a double and then
handed back through an integer-typed return slot without conversion.

## What this says about the shape

- The bug is in **return-type inference for a directly-returned expression**,
  not in `/` itself: `5 / 2` at module level, `y / 4` inside a function, and
  the same division bound to a local first (`e`) all give `2.5`.
- An explicit `-> float` is a complete workaround (`d`).
- Two different wrong answers from one cause: with an *unannotated* parameter
  the result is truncated (`2`), with an annotated one the bits are
  reinterpreted. The truncating arm at least looks like a number; the
  reinterpreting arm does not, which is the only reason this was noticed.
- Check the sibling shapes before closing
  (`devdocs/dev/normalise-dont-special-case.md`): other operators whose result
  type is wider than their operands — `**` with a negative exponent, and
  anything else that promotes int→float — reached through a bare
  `return <expr>`.

## Upward compatibility

Clear-cut under the N rule: this is code CPython accepts and runs, producing a
different value under NilPy. Not a divergence to record in
`devdocs/dev/nilpy-semantics-divergences.md` — a defect.

## Gate

`make test-nilpy` is superseded by the per-fix loop; add a `.npy` regression
test covering all five arms above and wire it into the Makefile's enumerated
list (`devdocs/progress` history: a test file that is not enumerated is not a
test).

## Log
- 2026-08-19 — filed from a Track D documentation verification pass.
