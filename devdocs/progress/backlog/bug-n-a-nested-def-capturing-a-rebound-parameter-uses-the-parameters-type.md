---
track: N
prio: 58
type: bug
owner: unassigned
blocked-by: []
summary: "A nested def that captures a REBOUND parameter resolves the name to the parameter, not to the private slot the rebinding created — so `x /= 2` then a closure reading `x` fails with `invalid IR node reference in store_sym`, and rebinding to a str gives a runtime TypeError. Capturing a plain LOCAL of any type works, and capturing a rebound VARIANT parameter works, which is what localises it."
---

# A nested def capturing a rebound parameter uses the parameter's type

- **Type:** bug (Track N) — a compile fault on one shape, a wrong runtime type
  on another.
- **Found:** 2026-08-27 while resolving
  [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]].
- **Measured:** at pinned **v383** (`18392d1d3181`) and at HEAD. **Pre-existing
  and unchanged** by the sibling fix — the messages differ at the two shas but
  both are wrong at both.

## Repro

```python
def o(x: int):
    x /= 2
    def inner():
        return x + 1
    return inner()
print(o(5))                     # CPython 3.5
```

```
v383: pascal26:5: error: invalid IR node reference in store_sym
HEAD: pascal26:5: error: invalid IR node reference in store_sym
```

...and the same shape rebinding to a string compiles and then fails at run time:

```python
def o(x: int):
    x = "s"
    def inner():
        return x + "t"
    return inner()
print(o(5))                     # CPython "st"
```

```
v383: TypeError: unsupported operand type(s) for +: 'int' and 'str'
HEAD: TypeError: expected a number, got str
```

## The boundary, which is what points at the cause

| shape | verdict |
| --- | --- |
| capture a plain **float** local | works — `2.5` |
| capture a plain **int** local | works — `3` |
| capture a plain **str** local | works — `st` |
| capture a rebound **variant** parameter | works — `2` |
| capture a rebound **typed** parameter | **broken**, both shapes above |

Capturing works for every ordinary local, and works for a rebound VARIANT
parameter — which is the one case that has had a private slot since
[[bug-nilpy-rebinding-a-list-parameter-aliases-the-callers-list]]. So the
capture scan handles a private slot fine; it does not find *this* one.

The likely difference is WHEN the slot is created. The variant slot is
allocated **before** `PyCollectLocalsAST`; the typed slot the sibling fix adds is
allocated **after** it (it needs the constraint table to know the type) and the
pass is then re-run. Moving the typed slot earlier — with a provisional type,
patched afterwards — would make the two identical and is the first thing to try.
Measure it; do not assume it.

## Gate

Both repros match CPython, plus the four control rows in the table above, plus a
`nonlocal` rebinding of a captured parameter.
