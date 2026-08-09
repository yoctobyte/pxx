---
prio: 60
track: N
type: bug
blocked-by: []
---

# A module name rebound INSIDE a block reads as garbage

- **Type:** bug (NilPy, **silent garbage / crash**) — **Track N**
- **Found:** 2026-08-09, reducing a realistic config reader.
- **Status:** FIXED the same session.

```python
cfg = {"w": {"h": "1"}}
sec = {"z": "0"}          # module level: a dict, so tyClass
for k in ["w"]:
    sec = cfg[k]          # a SUBSCRIPT yields a VARIANT
    print(len(sec))       # CPython 1     pxx 106954864
```

`len()` returned a pointer read as a length; `sorted(sec.keys())` printed `[]`
or **SEGFAULTED** depending on heap layout. Lists behave the same.

## Why prio 60 — it is the most ordinary shape found all session

```python
current = {}
for k in keys:
    current = table[k]
    ...
```

No prior binding works. Rebinding OUTSIDE a loop works. It is specifically the
pair, which is why it survived every API sweep and only showed when a realistic
program was run.

## Cause

The module pre-pass recognises only a few RHS shapes inside a block — it must
not trial-parse a name it cannot yet see, or it Errors and halts the whole
compile. A **subscript** was not one of them, so the block binding contributed
nothing and the name kept its module-level `tyClass`, while the value written
was a variant.

Three shapes were missing, all now recognised as token peeks with no parse:

| shape | element type |
| --- | --- |
| `name = other[k]` | variant |
| `for x in name.values()` / `.keys()` | variant |
| `for x in list(...)` / `sorted(...)` / `reversed(...)` | variant |

`.items()` is still deliberately unhandled — it binds a TWO-name target, which
that arm does not do. The three wrappers are named individually rather than
accepting any call, because an arbitrary call's element type is exactly what
this arm must not guess.

This is the third hole of the same shape found tonight; the first was
[[bug-nilpy-block-nested-scalar-then-class-rebind-loses-widening]]
(`name = Cls(...)` inside a block). The arm's safe-shape list is where this
family lives.

## Verified

`test/test_nilpy_module_name_rebound_in_a_block.{npy,expected}` (`.expected`
from CPython): all three shapes, dicts and lists, plus the controls that carry
the weight — no prior binding, rebinding outside a loop, a `str` loop target, an
augmented accumulator, and the INT ACCUMULATOR (`n = n * 2` in a loop) that this
block arm exists for in the first place and which must keep promoting rather
than widening to a variant.

**Whole-suite control:** all 480 `test_nilpy_*.npy` run under HEAD and under the
PINNED binary and the two difference-lists compared. **Zero regressions** — every
test that differs under HEAD differs identically under pinned — and 30
improvements, which are this session's fixes. `gate.sh quick` GREEN.
