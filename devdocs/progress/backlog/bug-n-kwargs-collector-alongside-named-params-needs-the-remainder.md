---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`def f(a=1, **kw)` called as `f(**{'a':5,'x':7,'y':8})` must give a=5 and kw={'x':7,'y':8} — the collector takes the UNCONSUMED keys. pylib has no helper that subtracts consumed names, and adding one is compiler/builtin/** which NEEDS A PIN, so this is coordinator-scheduled, not worker-startable."
---

# A `**kwargs` collector beside named parameters needs the remainder

- **Type:** bug (NilPy call lowering) — **Track N** by ownership, but see the
  pin note: it cannot be shipped from a worker session.
- **Split from** [[bug-n-star-forwarder-spreads-a-dict-onto-a-kwargs-callee]],
  fixed 2026-08-17 for the `kwIdx = 0` case only.

## Repro

```python
def f(a=1, **kw):
    return a * 100 + len(kw)

print(f(**{"a": 5, "x": 7, "y": 8}))
```

| | |
| --- | --- |
| CPython | `502` — `a=5`, `kw={"x":7,"y":8}` |
| pxx | `TypeError: forwarded call got 3 arguments, expected 2 to 2` |

## Why it was left failing rather than half-fixed

The collector case was fixed for a callee whose ONLY parameter is the collector,
where the whole dict goes in and nothing is consumed first. Extending the same
code to `kwIdx > 0` is a two-line change and would be **wrong**: it would hand
`kw` the entire dict, answering `len(kw) = 3` where CPython says 1. A wrong
value is worse than the error, so `kwIdx > 0` is explicitly reset to -1 in
`PyStarForwardCall` and keeps the old behaviour.

## What it needs, and why a worker cannot ship it

A runtime helper that returns the dict minus a set of consumed names —
`pystar_kwrest(d, n1, n2, ...)` or equivalent. `pylib.pas` today has
`pystar_arg_kw`, `pystar_has`, `pystar_argc`, `pystar_check_arity` /
`_kw`, `pystar_no_kwargs`, and nothing that subtracts.

`pylib.pas` is `compiler/builtin/**`, so the change **needs
`make stabilize-fast && make pin`** — Track B and the lib tests build with
`$(PXX_STABLE)` and cannot see an unpinned builtin. A pin holds the repo lock
and stalls every lane, which makes it coordinator-scheduled. **Do not claim this
as a worker.** (`devdocs/dev/session-roster.md`.)

## Sketch, once someone with the pin takes it

- `pystar_kwrest(d: TPyDict; const names: array of AnsiString): TPyDict` — a
  copy of `d` without the listed keys. The frontend knows the named parameters,
  so the name list is a compile-time constant, exactly as `pystar_arg_kw`
  already receives a name literal per slot.
- In `PyStarForwardCall`, stop resetting `kwIdx > 0` to -1; set
  `total := kwIdx` (the named parameters are the ones before the collector) and
  assign `pystar_kwrest(dict, <the kwIdx names>)` to the collector's slot
  instead of the dict itself.
- The arity guard stays the list-only `pystar_check_arity` — keys landing on
  named slots must not count as positional arguments. Note the guard's dict
  splice is conditional on the same flag; both must move together, which is the
  step that was got wrong once already.
- CPython also raises `TypeError: got multiple values for argument 'a'` when a
  key duplicates an explicitly-passed positional. Not modelled; decide whether
  to implement or leave it.

## Gate

`make compiler/pascal26` + a `.npy` diffed against CPython covering `f(**d)`
with keys that do and do not match named parameters, zero remainder, and
`test/test_nilpy_kwargs_collector_forward.npy` staying green. Then
`tools/gate.sh quick` **before committing**, so the FPC seed canary runs rather
than printing SKIP — plus `stabilize-fast` + `pin` for the pylib half.
