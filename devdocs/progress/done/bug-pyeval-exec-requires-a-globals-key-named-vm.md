---
summary: "pyeval: exec()'s env must contain a key literally named \"vm\" or every host call fails — CPython has no such rule"
type: bug
track: N
prio: 45
---

# `exec(src, env)` refuses a host call unless `env` has a `"vm"` key

- **Type:** bug (NilPy runtime — `compiler/builtin/pyeval.pas`) — **Track N**
- **Opened:** 2026-07-31 by Track B, gating [[feature-lib-pyexec]]'s public
  contract from a `.npy` rather than from the uforth corpus it was built for.

## Repro, diffed against CPython

```python
b = B()
env1 = {"push": b.push}                 # no "vm"
env2 = {"vm": b, "push": b.push}
exec("push(41 + 1)", env2)   # ok, both
exec("push(41 + 2)", env1)   # CPython: fine.  pxx: dies
```

```
pxx:      with-vm 42
          pyeval: host call push but no "vm" in globals
CPython:  with-vm 42
          without-vm 43
```

## Why it matters

The ticket that built this interpreter states the contract as *"semantics
matching CPython's explicit-dict form: no ambient scope capture, the host
passes name -> value bindings"*. A binding named `vm` is not part of that
contract — it is uforth's variable name, and it has leaked out of the corpus
that drove development into the general surface.

Any other consumer writes `{"canvas": c, "draw": c.draw}` or
`{"doc": d, "emit": d.emit}` and every host call fails, with a message that
names an identifier the caller never wrote and cannot guess the significance
of.

It is at least LOUD — it errors rather than silently calling the wrong thing.

## Where to look

The host-call path in `compiler/builtin/pyeval.pas` looks the receiver up by
the fixed name `vm` instead of taking it from the bound method's own
`{recv, method-ref}` pair, which is where it already is: `push` resolves
correctly as a bound method, so the receiver is in hand before the lookup
happens.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` running the repro
above with env keys that are NOT called `vm`, diffed against CPython.

## Log
- 2026-07-31 — resolved, commit 6ec550c1f274448d6a5c944b01f100ab1320af7c.
