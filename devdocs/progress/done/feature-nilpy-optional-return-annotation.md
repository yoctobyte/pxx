---
track: N
prio: 55
type: feature
---

# NilPy: `-> ret` is MANDATORY on every def; Python makes it optional

Found while writing `test/test_nilpy_kwargs.npy` (feature-nilpy-keyword-args,
commit 66685acc) — every def in that file had to grow a `-> None` that CPython
does not need. It cost three build-edit cycles to diagnose, because the cascade
is misleading: a class whose `__init__` header failed to parse simply is not
registered, so the *next* statement fails with
`Nil Python: annotate the type / too dynamic` on an unrelated line.

## Repro

```python
def f():
    print(1)
f()
```

```
pascal26:1: error: unexpected token
  near:  f   >>>
```

Same for `def f(a: int):`. Only `def f(a: int) -> None:` parses. CPython accepts
all three.

## Shape

The def-header parser (`compiler/pyparser.inc`, the `Expected: - in ->` site)
requires the arrow unconditionally. It should treat a missing `-> ret` as
`-> None` — the return type is already inferred elsewhere for nested defs, so
the information is available; what is missing is accepting `:` where the arrow
is expected.

Note the diagnostic quality issue too: `Expected: - in ->` names a character,
not the construct. A def whose header does not parse should say so, and the
class-registration cascade above should not surface as "too dynamic" on a later
line.

## Gate

`test-nilpy` green with a `.npy` case (unannotated def, unannotated method,
unannotated `__init__`) diffed against CPython, plus `--tier quick` and
self-host byte-identical.

## Log
- 2026-07-20 — resolved, commit HEAD.
