---
summary: "nilpy: a Python stdlib import silently binds to a same-named Pascal RTL unit (import json -> lib/rtl/json.pas)"
type: bug
track: N
prio: 60
---

# nilpy: `import json` binds to the RTL's Pascal `json` unit

- **Type:** bug (Nil-Python frontend, import resolution) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — hit compiling songformatter's `SongFormatter.py`
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

A one-line program:

```python
import json
```
```
pascal26:64: error: array of const requires the builtinheap unit (use an array/heap feature)
```

The line number is fiction (see below). What actually happens: NilPy maps `import
X` onto the Pascal unit resolver's `uses X`, so `import json` resolves to
`lib/rtl/json.pas` — a **Pascal** JSON unit with a Pascal API, nothing like
Python's `json`. It then fails because that unit needs `builtinheap`, which a
`.npy` program does not auto-pull the way it auto-pulls `pylib`.

## Why this is a bug and not a missing feature

The mechanism is deliberate and useful — it is exactly how
[[feature-nilpy-re-module]] provides `import re` with no frontend change, by giving
the unit the Python module's name AND the Python module's shape. The bug is that
it applies to names where the shape does NOT match: any Python stdlib module whose
name collides with an RTL unit binds to Pascal code, and the failure appears as a
confusing internal error rather than "json is not supported yet". Worse, a
collision where the Pascal unit happens to compile would bind Python calls to a
Pascal API and fail (or misbehave) further downstream.

Current collisions worth checking: `json`, `math`, `dns`, `net`, `http`,
`hashing`, `image`, `classes`, `collections`, `re` (intended), `random`.
`math` is the sharp one: Python's `math.sqrt` vs the RTL's `math` unit.

## Two things to fix

1. **Decide and implement the policy** for a stdlib name that resolves to a
   non-Python-shaped unit. Options: an allow-list of names that ARE Python shims
   (currently just `re`), with everything else reported as "module X is not
   supported yet"; or a `pylib/`-prefixed search path for Python shims so the
   Python namespace is separate from the RTL one. The second is cleaner long-term
   and does not need a list to be maintained. This may deserve a Track U
   `decide-` if the call is not obvious.
2. **Auto-pull `builtinheap` for `.npy` programs** the way `pylib` is pulled, or
   pull it on demand when a used unit needs array-of-const. Independently of the
   naming question, a nilpy program that reaches array-of-const code should not
   have to say so itself — it has no `uses` clause to put it in.

## Also: the diagnostic's line number is wrong

Every variant reports **line 64** regardless of the file: a 1-line program, a
4-line prefix and the full 586-line file all say 64. So the error carries a line
from somewhere else entirely (probably a position inside the *used unit*, reported
against the main file). Fix the attribution, or say which unit the error came
from — a wrong line number sends the reader hunting in the wrong file.

## Gate

`make test-nilpy` green with a `.npy` case per decision (a clear diagnostic for an
unsupported stdlib module, and a working shim for whatever is allow-listed), +
`--tier quick` + self-host byte-identical.
