---
prio: 50
track: N
type: bug
blocked-by: []
---

# A name assigned from a CALL, then reused as a for-loop target, SEGFAULTS

- **Type:** bug (NilPy, **crash**) — **Track N**
- **Found:** 2026-08-09, reducing a realistic config-reader program that kept
  crashing after two other bugs in it were fixed.
- **Owner:** —

```python
D = {"a": "1"}

def merged(s):
    m = dict(D)
    m.update(s)
    return m

cfg = {"w": {"h": "1"}}

for name in sorted(cfg.keys()):
    sec = merged(cfg[name])       # `sec` bound from a CALL
    print(sec["h"])

allkeys = set()
for sec in cfg.values():          # ...and reused as a LOOP TARGET
    allkeys |= set(sec.keys())
print(sorted(allkeys))            # SIGSEGV
```

## Narrowed — three one-line variations settle it

| change | result |
| --- | --- |
| as written | **SIGSEGV** |
| `sec = cfg[name]` instead of `sec = merged(...)` | works |
| rename the first binding to `other` | works |

So it needs BOTH: the name bound from a function CALL, and the same name later
used as a for-loop target. Either alone is fine.

## Why it is worth 50

Reusing a short name like `sec`, `row` or `item` for the same KIND of thing in
two loops is ordinary style, and the failure is a crash with no diagnostic. It
also survived two other fixes in the same program, so it is independent of them.

## Where to look

The first binding types `sec` from `merged`'s return (a `TPyDict` class); the
for-loop target then rebinds it to a variant element. That is the same
"one name, two representations" family as
[[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]] (fixed
2026-08-08, unrelated CLASSES widen to a variant) — but here the two are not
unrelated classes, so that widening does not fire and the loop lowering and the
call result disagree about the slot.

Start with `PXXDBG=n.locals` on the repro to see what `sec` is typed as, and
compare against the working `sec = cfg[name]` variant, which is the control that
removes the call from the picture.

## Gate
`.npy` diffed against CPython: the repro; the same shape with the loop first and
the call-binding second; a def-local version as well as module scope; and the
two one-line variations above as controls, so a fix cannot pass by making only
the reported ordering work.
