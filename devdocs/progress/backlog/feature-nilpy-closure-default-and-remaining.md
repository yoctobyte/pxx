---
track: N
prio: 45
type: feature
---

# NilPy: remaining uforth walls past ~88% (closure-captured defaults, then exec)

Hangs off [[feature-nilpy-corpus-uforth]]. As of 2026-07-21 the wall is
uforth.py:3829 — the first parse error is now this far in, after ~90 features
landed this session (267 -> 3829, ~88% of the 4357-line file).

## The current wall (3829)

```python
def _compile_name_xt(vm2: VM, target: Word = w) -> None:
```

A parameter default that is a CAPTURED VARIABLE (`w` from the enclosing scope),
Python's by-value loop-variable capture idiom. NilPy requires a CONSTANT default
(None/bool/int/str). This is closure capture expressed as a default: the
nested-def capture machinery (PyQueueNestedDef) already captures enclosing
locals the body reads as trailing params — a non-constant default that names an
enclosing local could be folded into that same capture, evaluated at def time.

## What still remains after it

The wall has been bouncing between nested defs (3994 -> 3967 -> 3846 -> 3829) as
each is fixed, because uforth registers ~200 native-word bodies as nested defs
and the first failing one changes. Expect a tail of small per-def issues of the
same kind already handled (variant subscript/slice, dynamic attrs, method
chains) plus:

- **Closure-captured parameter defaults** (this wall).
- **Variant slice ASSIGN** — `mem[a:b] = src` where mem is a variant holding
  bytes (a first attempt was reverted for a runtime bug; the READ works).
- **exec() actually running** — [[feature-lib-pyexec]]. exec() compiles as a
  stub; the native-word PYTHON blocks it should evaluate do not run. This is the
  milestone-3 subsystem and the real remaining work for a WORKING uforth.

## Status honestly

The file PARSES ~88% of the way. Reaching a compiled binary needs the tail of
per-def fixes above; reaching a RUNNING uforth needs pyexec. Both are scoped;
neither is a single edit.
