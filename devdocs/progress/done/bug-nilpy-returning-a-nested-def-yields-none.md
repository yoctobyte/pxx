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

## History — it used to be a documented gap, now it is silent

[[feature-nilpy-nested-def-as-value]] (prio 15, SUPERSEDED) described exactly
this shape as "not supported", and its successor
[[feature-nilpy-function-values]] landed the function-value machinery. So the
support arrived — a nested def as a value now COMPILES — but the returned value
is None. That is a worse failure than the old one: the diagnostic went away and
the wrong answer stayed. Hence a bug at prio 70 rather than a feature at 15.

Found by sweeping functions/closures/defaults/keyword-args/recursion/globals
against CPython; everything else in that sweep matched, including
`add(b=3, a=4)`, a default argument, recursion, `global`, a lambda in a name,
and a list of lambdas indexed and called.

## Measured 2026-07-30 — the value is WRAPPED, and the wrapper is what fails

`PXXDBG=a.ir:mk` on two programs that differ only in whether the returned def
is nested:

```
returning a TOP-LEVEL def (works, prints 2):
  0: unknown  a=952                 tk=17     <- AN_PROCADDR
  1: lea      a=263 [sym=$pyresult]
  2: var_store a=1 b=0 c=17                   <- the ADDRESS goes straight out

returning a NESTED def (prints None):
  0: unknown  a=953                 tk=17     <- AN_PROCADDR
  1: arg a=0 b=3
  2: const_int ival=0  tk=13
  3: arg a=2 b=5
  4: const_int ival=1  tk=13
  5: arg a=4
  6: call a=799 b=1                 tk=17     <- WRAPPED: f(addr, 0, 1)
```

So `mk` does build and return something; the plain-address path is the one that
works, and the wrapper's result is what the call site then cannot invoke. The
capture count is 0 in this program (the middle argument), so the wrapper is
being built even with nothing to capture — `PyMakeBoundFnValue` (pyparser.inc)
is the shape to look at, and whether the call site knows the resulting tag.

`print(mk()(1))` fails identically, so it is not about binding to a name.

## Two neighbouring gaps found while narrowing, worth their own tickets

- `def mkl(): return lambda x: x + 1` then `f = mkl(); f(1)` does NOT COMPILE
  ("unexpected token"), while the same with a parameter
  (`def mk(n): return lambda x: x + n`) does. The zero-parameter enclosing form
  is the difference.
- Calling a function-valued LOCAL inside a def — `def go(): g = mkl(); g(1)` —
  does not compile either ("unexpected token near g"), while the identical code
  at module level does.

## Gate

`make test-nilpy` + self-host byte-identical, plus returning a nested def with
and without capture, storing one in a container, and passing one to a
`Callable[...]` parameter.

## Log
- 2026-07-30 — resolved, commit 575c69e08.
