---
track: N
prio: 70
type: bug
---

# `return inner` — a nested def returned as a value — yields None

```python
def mk(n: int):
    def inner(x: int) -> int:
        return x + n
    return inner

f = mk(100)
print(f(1))        # CPython: 101     pxx: None
```

No capture is needed to trigger it:

```python
def mk():
    def inner(x: int) -> int:
        return x + 1
    return inner
print(mk()(1))     # CPython: 2       pxx: None
```

Silent — no error, no crash, just None where a callable belongs, and then
whatever the caller does with it.

The two neighbouring shapes are BOTH correct, which localises this tightly:

| shape | result |
| --- | --- |
| `return lambda x: x + n` | **correct** (101) — lifted lambdas return fine |
| `return inner(1)` (calling the nested def in place) | **correct** (101) |
| `return inner` (the nested def as a value) | **None** |

So nested defs work, closures work, and function VALUES work
([[project_nilpy_promo_adoption_landed]] / the callable-value family). What is
missing is the one route where a nested def's NAME is the returned expression:
the return path evidently does not resolve it to a function value the way the
lambda path does.

Found by sweeping functions/closures/defaults/keyword-args/recursion/globals
against CPython; everything else in that sweep matched, including
`add(b=3, a=4)`, a default argument, recursion, `global`, a lambda in a name,
and a list of lambdas indexed and called.

## Gate

`make test-nilpy` + self-host byte-identical, plus returning a nested def with
and without capture, storing one in a container, and passing one to a
`Callable[...]` parameter.
