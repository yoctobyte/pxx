---
track: N
prio: 60
type: bug
---

# Redefining a `def` silently does nothing — the FIRST body still runs

```python
def f():
    return 1
def f():
    return 2
print(f())        # CPython: 2     pxx: 1
```

No error, no warning. In Python a `def` is an assignment to a name, so the
second one replaces the first. pxx keeps the first and every later call goes to
it.

## Boundary — it is same-name-same-arity

| case | CPython | pxx |
| --- | --- | --- |
| `def f(): 1` then `def f(): 2` | `2` | **`1`** |
| the redefinition inside `if True:` | `2` | **`1`** |
| `def f(): 1` then `f = lambda: 2` | `2` | **`1`** |
| `def f(a)` then `def f(a, b)`, call `f(1,2)` | `3` | `3` ✓ |
| `def m` twice inside a `class` | last wins | last wins ✓ |
| `def f(): 1` then `f = 5`, print `f` | `5` | `5` ✓ |

So a different ARITY resolves correctly, and methods resolve correctly, and
rebinding to a non-callable resolves correctly. It is specifically a callable
rebound to another callable of the same shape.

## Likely cause

Pascal overload semantics leaking into a language that has none. Two same-named
routines with the same signature are a redeclaration in Pascal; the frontend
registers the second and the call site binds to the first match rather than to
the name's CURRENT value. The class case works because methods go through a
different registration path (a class member table, where the later entry
overwrites).

Note this is the mirror of a rule that IS wanted elsewhere:
[[project_strict_fpc_umbrella_and_lax_default]] records that lax overload
behaviour is intended for the Pascal frontend. NilPy needs the opposite — a def
is a binding, not a declaration — so the fix belongs on the NilPy path only,
not in the shared overload machinery.

## Why it matters

Every "define a stub, then define the real one", conditional definition
(`if sys.platform == ...: def f(): ...`), test monkey-patch, and
`f = lambda: ...` override silently keeps the wrong body — and the program
behaves as if the second definition were never written. There is no diagnostic
anywhere, and the symptom appears wherever `f` is finally called.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
with CPython's own output. Watch the arity row: making the name rebind must not
break genuine same-name-different-arity resolution, which the corpus relies on,
nor the class-method path.
