---
summary: "nilpy: *args / **kwargs in a def signature"
type: feature
track: N
prio: 50
---

# nilpy: `*args` / `**kwargs` parameters

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
def f(a, b=2, *args, **kw):
    return a + b + len(args) + len(kw)
```
-> `error: Nil Python: expected parameter name near: a b *args`

Keyword arguments at the CALL site already work (`f(1, b=5)` returns 6), and
`print(..., sep=)`-style kwargs are handled ([[feature-nilpy-print-kwargs]], done)
— this is the callee side.

## Why it matters

songformatter's settings helpers forward through `getF(*args, **kwargs)` /
`getI(*args, **kwargs)` to `get()`, which is the standard thin-wrapper idiom. A
GUI façade over `tk.pas` will want it too: tkinter's whole API is kwargs.

## Shape

`*args` as a tuple/list parameter, `**kwargs` as a dict; forwarding a
`*args`/`**kwargs` on to another call is the case songformatter actually needs, so
the unpacking side at the call site belongs here as well.

## Gate

`make test-nilpy` green with a `.npy` case covering collection AND forwarding,
diffed against CPython, + `--tier quick` + self-host byte-identical.
