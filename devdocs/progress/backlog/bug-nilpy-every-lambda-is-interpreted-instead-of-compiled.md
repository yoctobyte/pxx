---
track: N
prio: 60
type: bug
summary: "Every NilPy lambda lowers to a pyeval SOURCE closure re-walked by the tree-walker per call — 6.9x slower than the same body as a nested def, and 69x slower than CPython, which is an interpreter. Even a capture-free lambda takes this path; the native pyboundfn lowering is never attempted."
---

# Every `lambda` is interpreted, not compiled

- **Type:** bug (performance + expressiveness) — **Track N** (`pyparser.inc`
  lambda lowering)
- **Found:** 2026-08-10, tracing why `TPyList.sort(key=)` cannot reach
  `PyCallKey1` ([[bug-nilpy-list-sort-method-missing]]). The unit tangle turned
  out to be a symptom of this.

## Measured

200 000 calls through `map(f, xs)`, three runs each, stable to ±0.06 s. The
`b_base` row builds the list and calls nothing; per-call cost is the difference.

| | total | per call | vs pxx `def` | vs CPython |
| --- | --- | --- | --- | --- |
| baseline (no call) | 0.08 s | — | | |
| pxx, `def keydef(v): return -v` | 0.28 s | **1.0 µs** | — | 10x slower |
| pxx, `lambda v: -v` | 1.46 s | **6.9 µs** | **6.9x slower** | **69x slower** |
| CPython, either form | 0.06 s | 0.1 µs | | — |

**pxx emits native code and still loses to CPython's interpreter by 69x on this
program** — because it is not running native code for the lambda at all.

Direct evidence, not inference: the literal body source `return - v` is present
in the lambda binary's strings and **absent** from the def binary.

```
strings b_lam_bin | grep -c 'return - v'   ->  1
strings b_def_bin | grep -c 'return - v'   ->  0
```

## Root cause

`pyparser.inc` ~6169 lowers **every** lambda to a pyeval source closure:

> *A `lambda p1, ...: <expr>` — lowered to a PYEVAL CLOSURE built from the body's
> SOURCE text: `pyclosure_src_new(params, 'return <expr>')` ... The body is
> re-tokenized by pyeval at build time.*

It is unconditional. The benchmark's `lambda v: -v` captures nothing and needs no
runtime binding, and still takes it.

Compare the **nested-def-as-value** path (`PyMakeBoundFnValue`, ~6754), which
does the right thing already: it builds `pyboundfn_new(addr, n)` — a real
compiled procedure address — and falls back to a source closure only when a
capture genuinely cannot travel as a register word (a managed string capture
would dangle) or defaults must bind per-invocation.

So the machinery to choose already exists and is already correct. **Lambdas
simply never attempt it.**

## Second cost, not just speed

The lambda body is limited to **pyeval's subset**, which is narrower than
NilPy's own language — the header lists attribute access, subscripts, method
calls, `def`, f-strings and arbitrary-precision ints as out of scope. So a
lambda cannot do things the same expression can do anywhere else in the
language. It errors honestly rather than misbehaving, but the ceiling is real
and surprising.

## Why this also explains the unit tangle

Because every lambda is a source closure, `PyCallKey1` must dispatch a closure
arm, so it must live in `pyeval` — and every `key=`-taking builtin (`sorted`,
`min`, `max`, `map`, `filter`) had to move up into the interpreter unit with it.
`TPyList.sort` is a method on a **pylib** class, cannot follow, and therefore
cannot take `key=` at all. `pyparser.inc`'s cross-unit keyword-overload fallback
exists only to paper over that split.

Fix the lowering and closures become **rare** (runtime-bound defaults only)
rather than the default for every lambda, which is the precondition that makes
the layering cleanup in [[bug-nilpy-list-sort-method-missing]] worth doing.

## Fix direction

Try the native path first, exactly as the nested-def case does: lower a lambda
to a lifted compiled procedure + `pyboundfn_new`/`_bind`, and fall back to
`pyclosure_src_new` only for the shapes that genuinely need build-time value
capture. The lambda body is an expression, so it is *easier* than the nested-def
case, not harder.

Do NOT start by optimising the tree-walker. The walker is the correctness
reference and should stay; the bug is that the hot path goes through it at all.

## Gate

The benchmark above showing the lambda per-call cost within ~1x of the `def`
row, the NilPy suite green, and a `test/` regression asserting a capture-free
lambda does not embed its body source in the binary (the `strings` check above
is a cheap, direct oracle for "did it compile or interpret").
