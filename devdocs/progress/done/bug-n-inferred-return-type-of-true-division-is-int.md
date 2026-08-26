---
track: N
prio: 88
type: bug
blocked-by: []
summary: "A def with NO return annotation whose return expression is `/` infers an int return: `return x / 2` truncates to 2 for an unannotated param, and for `def b(x: int)` prints 4612811918334230528 — the float's raw bit pattern reinterpreted as an integer. Silent wrong values, no diagnostic."
status: done
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

## Log
- 2026-08-26 — resolved by frank1-N-truediv. `gate.sh quick` GREEN, self-host
  fixedpoint byte-identical.

## Resolved 2026-08-26

**Where the result type was decided: `PyInferExprType`** — the TOKEN scan in
`compiler/pyparser.inc` that types an expression for the pre-passes (a def's
registered return type, a field's declared type). It has no binop dispatch at
all: it walks the tokens and `PyWiden`s the operand types it recognises, and
`PyWiden(Int64, Int64)` is Int64. So `x / 2` was an integer.

**How many sites shared the rule: five, four of which already had it.**
`FloatBinopResultTk` (the `/` binop, `pasparser_expr.inc`), the two augmented-
assignment sites here (`/=`, both calling `FloatBinopResultTk` and noting the
local as a float), and the codegen's force-jump to the double path
(`ir_codegen.inc:3694`). This token scan was the one owner with no copy —
which is exactly why `print(5 / 2)` and `r = x / 2; return r` were right while
`return x / 2` was not. Fixed by calling the same `FloatBinopResultTk` (not a
hardcoded `tyDouble`: on ESP, int/int under `/` is native Single).

A **sixth** owner turned up in the same function's caller: the bare-ident return
chase (`x /= 2` then `return x`) matched only `=`, so it never saw an augmented
true division. Given the `/=` arm in the same ordered walk, so a later plain
`x = 5` still wins.

**What the boundary shapes revealed.** Twenty-odd shapes, diffed against
CPython:

- Broken: `x / 2` unannotated, annotated, both-annotated; `7 / 2`; `x / 2 + 1`;
  `1 + x / 2`; `-x / 2`; `x / 2 / 2`; behind an `if`; in either arm of a
  conditional expression; via a plain local; and the class-field forms.
- Already correct, and kept so: `//`, `%`, negatives, `x / 2.0`, `x / y` on two
  unannotated names, `abs(x) / 2`, `x ** -1`, an f-string, a list literal,
  module level, a lambda, a comprehension, a default argument, `range(int(x/2))`.
- **The find the shapes paid for:** `return (x / 2)` was still wrong after the
  division fix. Every arm of this scan looks for its operator at DEPTH 0, so one
  redundant paren pair hides all of them at once — and not just this rule:
  `return (x > 1)` printed **1** instead of True, a second silent wrong value
  nobody had filed. Stripping a whole-range non-tuple paren wrapper once at the
  top of the scan fixes both and every future arm for free.

**Not a bisect.** Endpoint measurement (pinned v363 vs HEAD) showed the shapes
identical at both ends — latent since the scan was written, not newly
introduced.

**Nothing needs a Track A ticket.** `/` and `//` already lex to distinct tokens
(`tkSlash` / `tkDiv`) and lower to the right shared IR ops; the whole defect was
in N's own file. `FloatBinopResultTk` lives in `pasparser_expr.inc` but is only
being CALLED, not changed.

**Four sibling defects found and filed rather than folded in** — each proven
NOT to be about division by a control shape with no `/` in it:

- [[bug-n-a-field-takes-its-type-from-the-first-token-of-its-right-hand-side]]
  — `self.v = n + 1.5` is equally wrong. The naive reorder re-opens a filed
  segfault, so it needs its own gate.
- [[bug-n-a-fields-type-is-fixed-by-its-first-assignment-and-never-widened]]
  — `self.v = n` then `self.v = 1.5`. A local widens here; a field does not.
- [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]]
  — `PXXDBG=n.locals` shows the float IS noted (`tk=19`) and dropped because
  the symbol is `kind=2`, a parameter. Wrong with no return involved at all,
  which is why the `/=` chase arm above has no observable effect yet.
- [[bug-n-a-field-assigned-from-a-module-global-expression-is-refused]]
  — `G = 7 / 2` then `self.v = G` refuses to compile; `G = 3.5` is fine.

**Regression test:** `test/test_nilpy_true_division_return_type.npy` +
`.expected` generated from CPython 3, wired into **test-core** (which runs in
the quick tier — `test-nilpy` does not). Forty assertions: all five arms of this
ticket, every operand shape above, the `//` / `%` / negative / mixed-type
controls that must stay integer, division under a comparison and under `in`, and
the five redundant-paren shapes. The pinned binary fails 15 of the 40 lines.
- 2026-08-26 — resolved, commit PENDING-COMMIT.
