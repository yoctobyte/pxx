---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# `return None` beside a container return hands back an unusable nil handle

- **Type:** bug (NilPy; valid CPython — silent wrong value, then SIGSEGV) —
  **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a dependency resolver whose
  `toposort()` returns `None` on a cycle and a list otherwise).

```python
def toposort(g):
    ...
    if len(order) != len(indeg):
        return None
    return order

print(toposort(cyclic))     # CPython None;  pxx []
```

`None` was correct for IDENTITY and wrong for everything else:

| | CPython | pxx (before) |
| --- | --- | --- |
| `type(x).__name__` | NoneType | NoneType ✓ |
| `x is None` | True | True ✓ |
| `bool(x)` | False | False ✓ |
| `print(x)` / `repr(x)` / `str(x)` / f-string | None | **`[]`** (`{}` for a dict) |
| `"%s" % x` | None | None ✓ |
| `len(x)`, `x[0]`, `1 in x`, `for q in x`, `x + [1]`, `x.append(1)` | TypeError | **SIGSEGV** |

The rendering half is the worse one: a plausible `[]` where the program meant
"no answer", with no diagnostic. `%s` was right because it boxes to a variant
first — which is the shape of the fix.

## Cause

`PyInferDefRetType` is built on "a `return None` says nothing about the type —
None is compatible with every result", and skips those returns. That holds for
every kind whose None is a value-domain sentinel (`0` for an int, a nil string
handle for a str), but **for a class the sentinel is a nil object pointer** and
every consumer dereferences it. The def was therefore typed `tyClass`, and the
None arm returned nil.

## Fix

A def that returns None on one arm and a class on another returns a **variant**.
That path is already correct today, and is not a new representation to invent: a
None boxes as `VT_EMPTY` and a container as `VT_OBJECT`, exactly how list
elements and dict values have always carried the two apart. Same call
[[decide-nilpy-optional-int-none-vs-zero]] made for `Optional[int]`.

Both spellings count — `return None` and a bare `return` are the same value in
Python, and fixing only one is the sibling-arm trap.

**Deliberately not covered:** falling off the END of a def also yields None, and
recognising that needs flow analysis rather than a token scan. Filed as its own
remaining arm rather than guessed at here.

## Found alongside, filed separately

`x[0]` on a None now raises nothing catchable: `pyeval.pas`'s `PySubscriptGet`
does `writeln(...); Halt(1)` where CPython raises TypeError/IndexError. That is
a whole family of uncatchable runtime aborts and is
[[bug-nilpy-pyeval-runtime-errors-halt-instead-of-raising]].

## Verified

`test/test_nilpy_none_beside_a_container_return.npy` — both arms of both
container kinds, every rendering path, a bare `return`, the consumers, a real
empty container as the control, and a def with no None arm keeping its class
result and its methods. Diffs clean against `.expected`, which is CPython's own
output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
