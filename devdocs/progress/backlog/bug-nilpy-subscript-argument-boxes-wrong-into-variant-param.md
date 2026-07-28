---
track: N
prio: 75
type: bug
---

# A SUBSCRIPT argument passed to a variant parameter arrives as garbage

Pre-existing (reproduces on `stable_linux_amd64/default/pinned`) and **silent**:
the program compiles clean and prints a pointer where a number belongs.

```python
d = {"n": 42}
l = [42]
v = d["n"]
print(max(v, 1))        # 42        — a variable is fine
print(max(d["n"], 1))   # 5233072   — CPython: 42
print(max(l[0], 1))     # 5233112   — CPython: 42
print(max(1, d["n"]))   # 5233232   — CPython: 42
```

Binding the subscript to a local FIRST works; passing the subscript expression
directly does not. Either operand position fails, and a list index fails the
same way as a dict key, so it is the subscript EXPRESSION that is mis-boxed,
not the container.

`min` shares the path and hides it whenever the other operand is the answer
(`min(d["n"], 1)` is 1 either way), which is exactly how this survived — the
wrong value is only visible when the subscript should win.

## Why it matters beyond max/min

`max`/`min` are just the two-argument variant helpers that happen to be easy to
call. The same boxing feeds every pylib entry point with a `const Variant`
parameter, so any of them can receive a subscript and see garbage. It also
blocked the `%` formatter
([[bug-nilpy-percent-string-format-garbage]]): three separate wirings of that
call were correct for literals, variables and tuples, and all three delivered
None for `"%s" % d["k"]`. That ticket's remaining question and this one are the
same question.

Note what DOES work, since it narrows the search a lot: `str(d["k"])`,
`len(d["k"])`, `int(d["s"])`, `abs(d["n"])`, `sorted([d["n"], 1])` and
`d["k"] + "!"` are all correct. So the general subscript lowering is fine, and
something specific to the two-argument variant call path (or to how those
helpers' parameters are declared) is not.

## Gate

`make test-nilpy` plus a `.npy` passing a dict subscript and a list index
directly into `max`/`min` in both operand positions, diffed against CPython —
and, once found, the same shape through one more `const Variant` helper to show
the fix is at the boxing and not at max/min.
