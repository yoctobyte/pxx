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
