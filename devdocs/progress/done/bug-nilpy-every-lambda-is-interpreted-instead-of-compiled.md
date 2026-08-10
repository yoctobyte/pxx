---
track: N
prio: 60
type: bug
summary: "Every NilPy lambda lowers to a pyeval SOURCE closure re-walked by the tree-walker per call — 6.9x slower than the same body as a nested def, and 69x slower than CPython, which is an interpreter. Even a capture-free lambda takes this path; the native pyboundfn lowering is never attempted."
status: done
owner: claude-N
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

## Resolved 2026-08-10 — the lift already existed; it was gated shut

The fix is far smaller than this ticket's "fix direction" assumed. A compiled
lowering was already built (`feature-nilpy-lambda-compiled-closure`): a lambda
is lifted to a real proc + `pyboundfn_new`/`_bind`, with the pyeval closure as
the fallback. It was simply unreachable for ordinary bodies.

`PyLambdaBodyIsLiftable` ended in:

```pascal
Result := (sawCall or nestedLambda) and (depth = 0);
```

**A lambda body had to CONTAIN A CALL to be compiled.** Its own comment gave the
reason: *"a body without a call already works through the pyeval closure, and
lifting it would be a behaviour change for no gain."* The premise is true — the
answers were always right — and the conclusion is what the measurement kills.
A second clause, `if bEnd - bStart < 3`, rejected one- and two-token bodies for
the same unstated reason.

Because a call was never the typical lambda body, the gate caught the most
ordinary lambdas in the language: `lambda r: r[1]` (a subscript — THE Python
sort-key idiom), `lambda v: -v`, `lambda x: x * 2`, ternaries, comparisons.

**Fix:** `Result := (depth = 0)`, and the token floor to `< 1`. The depth-0
token scan above it is the real gate and is untouched, so a body must still be
a flat expression built from tokens the lifter handles; anything it rejects
keeps the pyeval closure. `sawCall`/`nestedLambda` are now informative only.

### Measured, HEAD vs pinned

| 200k calls through `map()` | before | after |
| --- | --- | --- |
| `lambda v: -v` total | 1.46 s | **0.41 s** |
| per call | 6.9 µs | **1.65 µs** |

3.6x faster wall-clock. The residual gap to a plain `def` (1.05 µs/call) is
bound-fn dispatch versus a direct address, not interpretation.

**Route change proved directly, not inferred.** The interpreted path embeds the
body's source text in the binary; the compiled path does not. Over the 16-shape
sweep: `strings <bin> | grep -c '^return '` = **11 before, 0 after**.

**Answers unchanged.** All 16 shapes are byte-identical to CPython, and
byte-identical between `pinned` and HEAD — this moved the route, not the
semantics, which is exactly why the cost was invisible for so long.

### Tests

`test/test_nilpy_lambda_callfree_body_is_compiled.npy` (+ `.expected` generated
from CPython) pins the newly-lifted shapes. Deliberately a NEW file beside the
20 existing lambda tests.

Honest about what it is: it passes under `pinned` too, so it is **not** a
control for the route change — both routes give the same answers. It guards the
LIFT's correctness on shapes that never went through the lift before, which is
where a regression would land. Compiled-ness itself is asserted by the
`strings` oracle above, recorded here because it is not expressible as a `.npy`
assertion.

Also corrected a now-stale comment in
`test/test_nilpy_lambda_expression_body.npy`, whose `f9` case was documented as
"the control: a body with no call still takes the old path". Its assertion is
unchanged and still passes; only the claim about routing was falsified.

### Remaining scope — filed separately

Multi-parameter lambdas (`lambda a, b: a + b`) are **still interpreted**: the
lift is additionally gated on `nParams <= 1`, because the bound-fn bridge passes
a single argument. Correct, just slow. See
[[bug-nilpy-multi-parameter-lambdas-are-still-interpreted]]. The 1-parameter
case was the right first cut — every `key=`/`map`/`filter` callback is
1-parameter.

Gate: self-host fixedpoint converged, `tools/gate.sh quick` GREEN.

## Log
- 2026-08-10 — resolved, commit 9445b7ab3.
