---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`exec(src, {\"__builtins__\": {}})` — the restricted-exec idiom — raises NameError in CPython and silently resolves builtins anyway in pxx. The caller's explicit instruction to resolve names against THIS mapping is discarded, so working CPython code takes a different path. Upward-compatibility defect, split out of the cosmetic decide-nilpy-exec-injects-a-builtins-key."
---

# `exec` ignores a caller-supplied `__builtins__` mapping

- **Type:** bug (semantics / CPython parity) — **Track N**
  (`compiler/builtin/pyeval.pas`; exec's name resolution).
- **Found:** 2026-08-16, measuring
  [[decide-nilpy-exec-injects-a-builtins-key]] before elaborating it. That
  ticket is about a cosmetic key in `d.keys()`; this is the behaviour hiding
  behind it, and it is a defect rather than a design fork.

## Repro

```python
d = {"__builtins__": {}}
exec("n = len([1,2,3])", d, d)
print(d.get("n"))
```

| | result |
| --- | --- |
| CPython 3 | **`NameError: name 'len' is not defined`** |
| pxx (`stable_linux_amd64/default/pinned`) | **`3`** — resolved anyway |

## Why this is a bug and not a divergence

NilPy's contract is upward compatibility: *if code works on CPython, it must
work on NilPy.* Here a program that runs on CPython runs on NilPy **and does
something else** — it resolves names the author explicitly scoped away. That is
the "silent wrong behaviour" case the compat escape rule promotes to a bug in
the owning lane, not parity work to be parked.

It is also not the laxer-than-CPython case that
`devdocs/dev/nilpy-semantics-divergences.md` correctly files as a feature. Being
lax about a *restriction* is only harmless when no working program observes it;
here the whole point of the construct is the restriction.

## What CPython actually does (measured, all four contexts)

- The value `exec` injects into a fresh globals dict is `builtins.__dict__` —
  a **dict**, by identity, 157 keys — never a module object.
- It is injected into **globals only**; `exec("y=1", g, l)` leaves `l` as
  `{'y'}`.
- It is injected **only when absent**. A caller-supplied `__builtins__` is left
  untouched, and name resolution then goes through it — which is what makes the
  repro above raise.

pxx today does none of the three: no key, `g` comes back empty, and a supplied
mapping is ignored.

## Scope — deliberately the cheap half

This ticket is **only** "consult the mapping the caller supplied". It does NOT
require building a builtins dict when the caller supplied none — that is the
cosmetic half, it needs an enumerable builtin table, and it is parked on the
decide ticket with a live-alias footgun of its own (CPython's value is
`builtins.__dict__` by identity, so a faithful implementation would let
`d["__builtins__"]["len"] = ...` mutate the builtin namespace program-wide).

So the change is at exec's name-resolution path: when `globals['__builtins__']`
is present, builtin-name lookup goes through that mapping, and a miss is a
`NameError` rather than a fallback to the native builtin. Absent the key,
behaviour is exactly as today.

Note that pxx's `exec` is a genuine interpreter, not a stub — `len`, `str`,
`range`, and `for` loops all work inside it (measured) — so there is a real
lookup path to change rather than a feature to invent.

## Not a security claim

CPython's restricted exec is **not** a sandbox (`().__class__.__bases__` and
friends escape it), so this is not "pxx has a sandbox hole". The claim is
narrower and stands on its own: the name-resolution behaviour is well-defined,
observable, and used to evaluate config/template expressions against a
controlled namespace.

## Gate

`make compiler/pascal26` + the repro raising `NameError`, plus a positive case
(a supplied mapping containing `len` resolves it), then `tools/gate.sh quick`.
Touches `compiler/builtin/**`, so it carries the `stabilize-fast` + `make pin`
obligation.
