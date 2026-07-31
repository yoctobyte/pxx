---
summary: "nilpy: return a tuple — `return 1, 2` (and unpack at the call site)"
type: feature
track: N
prio: 50
---

# nilpy: tuple return

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
def two():
    return 1, "a"
a, b = two()
```
-> `error: Nil Python: expected newline after statement` at the `return`.

Tuple unpacking itself works — `a, b = 1, 2` and `w, h = "200x100".split("x")`
both compile and run (see `feature-nilpy-tuple-unpack`, done). Only the bare
tuple in a `return` is unparsed.

## Why it matters

Multiple return values without a wrapper type is everywhere in real Python.
songformatter's `tones_to_guitar` returns `"xxxxxx", [0,0,0,0,0,0]`, and the chord
parsing helpers return pairs.

## Gate

`make test-nilpy` green with a `.npy` case returning and unpacking pairs
(including mixed types) diffed against CPython, + `--tier quick` + self-host
byte-identical.

## Log
- 2026-07-31 — resolved, commit 83c2cb0e5.
