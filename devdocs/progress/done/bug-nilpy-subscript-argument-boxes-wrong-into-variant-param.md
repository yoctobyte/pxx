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

## Narrowed further — it is OVERLOAD RESOLUTION, not the subscript

Measured after filing:

- A USER def takes the same argument correctly:
  `def f(x: int) -> int: return x + 1` called as `f(d["n"])` returns 43, and so
  does an unannotated `def g(x)`. So `IRLowerCallArg`'s variant-to-scalar unbox
  DOES fire for a subscript argument — the general path is fine.
- `max` is OVERLOADED in pylib: `max(Int64, Int64)`, `max(Double, Double)` and
  a ONE-argument `max(l: TPyList): Variant`.
- `print(max([3, 9], 1))` — a two-argument call whose first argument is a list —
  fails to compile with the candidate list showing `max(class)`, i.e. the
  ONE-parameter overload is offered for a TWO-argument call.

So the shape is: a variant argument does not match `Int64`/`Double` exactly,
resolution falls through to the 1-parameter `max(TPyList)` overload, the second
argument is dropped, and the call yields that overload's Variant result — which
is the pointer that gets printed. `max(v, 1)` with the value bound to a local
works because the local's declared type resolves the two-parameter overload
directly.

That also explains why `min(d["n"], 1)` looked right: the same wrong overload
runs, and its answer happens to coincide when the other operand wins.

### Correction: arity is ALREADY filtered

Checked in the source rather than inferred: `MatchProcCall` (symtab.inc) gates
every type-match phase behind `ProcArityMatches`, which accepts a candidate only
when `ParamCount = nArgs`, or when the extra parameters all carry defaults. A
two-argument call therefore cannot select the one-parameter `max(TPyList)`
overload, and the `max(class)` line in the failed compile above is the CANDIDATE
REPORT listing every same-name proc — not the overload that was chosen. The
"drop the second argument" theory does not survive.

So the open question is narrower and still open: with `argTypes[0] = tyVariant`
the exact phase cannot match `max(Int64, Int64)`, and one of the later
compatible phases binds it — after which `IRLowerCallArg` should unbox the
variant into the Int64 parameter exactly as it does for a user `def f(x: int)`,
which is measured to work. Something between those two differs for an
overloaded builtin.

### Where to start next

Instrument the pick: log which proc index `MatchCallDelphiProcAddr` returns for
`max(d["n"], 1)` versus `max(v, 1)`, and compare it with the index for
`f(d["n"])`. That one line of output decides whether the fault is in the phase
that binds the overload or in the unbox that follows it — everything above is
consistent with either.

If the answer is "the overload set is the problem", the established alternative
in this codebase is distinct NAMES per operand type (`pyfloordiv_v` and friends)
rather than an overload set, precisely because
[[bug-a-len-of-variant-picks-wrong-overload]] showed a Variant argument picks
arbitrarily — a `pymax_v`/`pymin_v` pair selected by the frontend when either
operand is a variant would follow that precedent.

## Log
- 2026-07-29 — resolved, commit 4736360b0.
