---
summary: "nilpy: f-string format specs — {x:.2f}, alignment/width {s:>5}"
type: feature
track: N
prio: 50
---

# nilpy: f-string format specs

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
print(f"{3.14159:.2f}")     # runtime: format spec ".2f" on a value of variant tag 3 is not supported
print(f"{'F':>5}")          # width/alignment
```

Compiles, then fails at runtime with a clear message (good — not silent, unlike
[[bug-nilpy-percent-string-format-garbage]]).

## Scope

Precision `.Nf` on floats, integer width, and `<`/`>`/`^` alignment with a fill.
songformatter formats scores and pads labels; both are ordinary in real Python.

## Gate

`make test-nilpy` green with a `.npy` case diffed against CPython, + `--tier
quick` + self-host byte-identical.
