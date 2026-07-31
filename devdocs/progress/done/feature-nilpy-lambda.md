---
track: N
prio: 40
type: feature
---

# NilPy: real lambda expressions (function values)

`lambda p1, p2: expr` as a first-class value. Currently PARSED but reduced to a
None placeholder (ParseFactor -> PyParseLambdaStub), so a program that stores a
lambda compiles but the lambda body never runs.

uforth uses lambdas as native-word bodies: `vm.define_word("STATE",
native=lambda vm: vm.push(SYS_STATE_ADDR))`. These are called through the same
dynamic-dispatch / native path as exec'd blocks, which is milestone 3
([[feature-lib-pyexec]]) — so the stub is consistent with exec() also being a
stub for now.

## Shape

Synthesize a hidden function from the lambda (a proc with the lambda's
parameters and `return <expr>` as its body) and yield a reference to it — a
function NAME used as a value already works (see the dynamic-call test). Reuse
the nested-def machinery (PyQueueNestedDef): register a proc shell, capture any
enclosing locals the body reads as trailing by-value params, queue the body for
later compilation. uforth's lambdas capture only module globals (SYS_*
constants), so capture is minimal there.

## Gate

`test-nilpy` green with a `.npy` case storing a lambda and CALLING it (diffed
against CPython), + `--tier quick` + self-host byte-identical + fpc-check clean.

## Update (2026-07-26, probing songformatter — how the stub actually fails)

Measured against `stable_linux_amd64/default/pinned`. The stub's failure mode is
worse than "the body never runs":

| shape | result |
| --- | --- |
| `ops = {"d": lambda v: v*2}` then `ops["d"](4)` | **SEGFAULT** (exit 139) |
| `fs = [lambda v: v+1]` then `fs[0](5)` | prints an EMPTY value, no error |
| `g = lambda v: v+1` then `g(5)` | `error: unexpected token` (doesn't parse) |
| `rows.sort(key=lambda r: r[1])` | `error: undefined variable (key)` |

Calling the None placeholder crashes rather than diagnosing, so a program using
lambdas as values fails in the field instead of at build time. Until the real
implementation lands, calling a stubbed lambda should be a compile error.

songformatter needs this for `sorted(..., key=...)` and for dispatch dicts of
small handlers; see [[feature-demo-songformatter-pxx-target]] and
[[feature-nilpy-aggregate-builtins]].

## Already fixed — verified 2026-07-31, closing

Real lambda values landed since this ticket was filed (through the various
lambda-capture/dynamic-call/pyeval work referenced elsewhere in this
backlog). Re-measured every failure shape from the 2026-07-26 table
directly against CPython — all four now match:

| shape | now |
| --- | --- |
| `ops = {"d": lambda v: v*2}; ops["d"](4)` | `8` (matches) |
| `fs = [lambda v: v+1]; fs[0](5)` | `6` (matches) |
| `g = lambda v: v+1; g(5)` | `6` (matches) |
| `sorted(rows, key=lambda r: r[1])` | matches (the FUNCTION form; see below) |

One residual noted in passing, NOT part of this ticket's scope: `rows.sort(key=lambda r: r[1])`
(the in-place LIST METHOD) still fails — `TPyList has no method sort` — a
separate, narrower gap (`.sort()` itself, unrelated to lambda values; the
standalone `sorted()` function already works fine with a lambda `key=`).
Worth its own ticket if it matters for real code; not filed here to avoid
scope creep on an otherwise-closed item.

Added `test/test_nilpy_lambda_real_value.npy` — the existing
`test_nilpy_lambda_stub.npy` never actually CALLED a stored lambda value,
so this gap had no direct regression coverage despite the underlying
capability already working.

## Log
- 2026-07-31 — resolved, commit fba0429bd.
