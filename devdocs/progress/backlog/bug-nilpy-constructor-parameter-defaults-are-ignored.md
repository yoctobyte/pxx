---
prio: 60
type: bug
track: N
summary: "SILENT: __init__ parameter defaults are ignored entirely — `def __init__(self, v=7)` then `C()` leaves v as None, for CONSTANT defaults too. Ordinary methods honour their defaults; the constructor call path does not consult ProcParamDefault* at all."
---

# `__init__` parameter defaults are ignored

- **Type:** bug (NilPy, silent wrong value) — **Track N**
- **Found:** 2026-08-04, Track A+N overnight, while landing the METHOD half of
  [[bug-nilpy-non-constant-parameter-defaults-silently-become-none]].
- **SILENT.** The field is simply `None`; nothing is reported.

## Repro

```python
class C:
    def __init__(self, v=7):
        self.v = v
print(C().v)
```

```
CPython:  7
pxx:      None
```

## It is NOT the non-constant-default bug

That ticket is about defaults whose value is not a literal scalar. This one
fires for `v=7`, a plain constant, which that ticket lists as *working*
everywhere else. Ordinary methods in the same class do honour their defaults:

```python
class C:
    def __init__(self, v=[]):
        self.v = v
    def m(self, b=[3]):
        return b
o = C()
print(o.v, o.m())      # CPython [] [3]   pxx None [3]
```

## Pre-existing, verified against the pinned binary

Measured with `stable_linux_amd64/default/pinned` — a binary built before any of
tonight's changes, so the control removes the variable rather than editing text:

| repro | pinned (pre-change) | HEAD + method-defaults work |
| --- | --- | --- |
| `__init__(self, v=7)` | `None` | `None` (unchanged) |
| `__init__(self, v=[])` + `m(self, b=[3])` | `None None` | `None [3]` |

So the constructor half was already broken and is untouched by the method-default
evaluation that landed; that change only fixed the ordinary-method column.

## Where to look

A NilPy construction `C(...)` is not an ordinary method call: the frontend builds
a GetMem-shaped call carrying a NEGATIVE proc id (see `ResolveNodeRec`'s
construction branch, `symtab.inc`, and `PyParseClassMethodCall`'s ctor route), so
the arity/default machinery the method path uses does not obviously run for it.

The two consumers that fill an omitted argument from `ProcParamDefault*` are
`DefaultArgValueNode` (`parser.inc:2641`, the funnel behind the four fill sites)
and the IR-level loop (`ir.inc:8305`). Measure which — if either — is reached for
a construction before changing anything; the method half of the parent ticket was
first built against the wrong one of these two and stored the symbol correctly
while the call site never read it.

Note `__init__` is registered as `create` (`PyMethodName`, `pyparser.inc:16545`),
so anything looking the ctor up by its Python spelling finds nothing — that is a
real trap on this path, though it is not by itself the cause here (fixing the
lookup in `PyEvalMethodDefaults` did not change the result, which is what
pointed at the CALL path rather than the registration).

## Gate

`make test-nilpy` + self-host byte-identical. Extend
`test/test_nilpy_param_defaults_nonconstant.npy` (it now carries the method rows)
with: a constant ctor default, a container ctor default, an explicit argument
overriding each, and a ctor default alongside an ordinary method default in the
same class — all diffed against CPython.
