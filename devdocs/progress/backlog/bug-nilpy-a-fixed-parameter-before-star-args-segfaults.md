---
summary: "`def __init__(self, tag, *rest)` — a fixed parameter BEFORE `*args` segfaults on ordinary construction. `*args` alone works, so only the mixed shape is broken; no diagnostic, the crash is inside the constructor."
type: bug
track: N
prio: 55
found-by: claude-AN
---

# A fixed parameter before `*args` segfaults

- **Type:** bug (crash, no diagnostic) — Track N (Nil-Python frontend)
- **Opened:** 2026-08-10
- **Found by:** writing the gate cases for [[feature-nilpy-class-as-a-value]];
  the shape is unrelated to that feature (it fails identically without it).

## Repro

```python
class P:
    def __init__(self, tag, *rest):
        self.tag = tag
        self.n = len(rest)
    def show(self):
        print("P", self.tag, self.n)

o = P("u", 9)
o.show()
```

CPython prints `P u 1`. pxx compiles clean and **SEGFAULTS**.

Confirmed pre-existing at `stable_linux_amd64/default/pinned` (v256), so it is
not the class-as-a-value work.

## The boundary, measured

| shape | result |
| --- | --- |
| `def __init__(self, *args)` | **works** (`S(1, 2)` → `n == 2`) |
| `def __init__(self, tag, *rest)` | **segfault** |

So it is not `*args` in a constructor and not construction — it is a fixed
parameter *before* the star that breaks. Worth checking the plain-`def` twin
(`def g(a, *rest)`) before deciding the fix belongs to the ctor path: if that
fails too, the packing is wrong wherever the star index is not 1, and the
constructor is only where it was noticed.

## Why it rates a 55

It is the standard thin-wrapper shape — `def __init__(self, name, *opts)` — and
it crashes rather than diagnosing, which is the expensive kind. It is also
narrow: the star-index-0 case works, so this is very likely one off-by-one in
the argument packing rather than missing machinery.

## Related

[[feature-nilpy-star-args-kwargs]] is the broad callee-side `*args`/`**kwargs`
feature (unfinished). This is filed separately because it is a SILENT CRASH in
a shape that already parses and already half-works, not a missing feature.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`(self, a, *rest)`, `(self, a, b, *rest)` and the plain-`def` twin, diffed
against CPython via `tools/pydiff.py run`.
