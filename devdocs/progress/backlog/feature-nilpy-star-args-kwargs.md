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

## Update (2026-07-26) — this is what blocks the tkinter façade, measured

The façade in [[feature-nilpy-tkinter-facade]] cannot be written without it, and the
reason is sharper than "tkinter uses kwargs". Two measurements:

1. **Keyword arguments must fill a contiguous PREFIX of the parameters.** Skipping
   an optional fails:

```python
class W:
    def __init__(self, master: str, width: int = 0, text: str = "") -> None: ...
W("root", width=7, text="hi")     # works
W("root", text="skipped-width")   # error: W() needs a value for every field
                                  #        before the last one given
```

   So a façade CANNOT just declare the ~40 tkinter option names as optional
   parameters and let callers pick a few — which was the obvious way to avoid
   needing `**kwargs` at all. Every real call skips most options
   (`tk.Canvas(self, highlightthickness=0)`, `tk.Label(self.content, text=k,
   anchor="e")`).

2. `__init__` must be annotated `-> None` or the class is rejected. Unrelated to
   kwargs, and a fine rule, but worth knowing when writing shim classes.

Fixing the prefix restriction alone (bind keyword arguments by NAME, leaving
unmentioned optionals at their defaults) would unblock a declared-parameter façade
without needing `**kwargs` at all, and is a smaller change. Real `**kwargs` is
still wanted for forwarding wrappers (songformatter's `getF(*args, **kwargs)`), but
the tkinter path only needs by-name binding.

Recommended split: (a) keyword arguments bind by name, any subset — small, unblocks
the façade; (b) `*args`/`**kwargs` collection and forwarding — the original scope.
