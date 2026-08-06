---
track: N
prio: 70
type: bug
status: done
owner: claude-AN
summary: "NilPy: a `for i in range(...)` counter is allocated tyInteger (4 bytes), so a bound at or past 2^31 wraps — range(3000000000, 3000000003) starts at -1294967296 and loops forever, while list(range(...)) of the same bounds is correct"
---

# A counted-loop counter is 32-bit, so a large range never terminates

- **Type:** bug (silent wrong value + hang) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`.

## Measured (before, self-hosted binary at `08bea9451`; identical on `pinned`)

```python
for i in range(3000000000, 3000000003):
    print("i", i)
print("done")
```

```
i -1294967296
i -1294967295
i -1294967294
…                 <- never reaches `done`; killed at the timeout
```

`-1294967296` is 3000000000 taken mod 2^32, read signed. The counter can never
reach 3000000003, so the loop is unbounded.

`range()` itself is fine — only the counted-loop lowering is wrong:

```python
print(list(range(3000000000, 3000000003)))   # [3000000000, 3000000001, 3000000002]  CORRECT
print(len(range(3000000000, 3000000003)))    # 3                                     CORRECT
```

The boundary is exactly 2^31: `range(2147483645, 2147483647)` iterates correctly,
`range(2147483647, 2147483650)` wraps.

## Cause

`compiler/pyparser.inc`, the `range()` arm of the `for` parser:

```pascal
    symIdx := PyProgSym(name);
    if symIdx < 0 then symIdx := AllocVar(name, tyInteger);   { 4 bytes }
```

`AllocVar` is called directly, bypassing `PyNoteLocalType` — which is where
every other inferred NilPy local now gets widened to a 64-bit cell
([[bug-nilpy-augmented-assignment-truncates-to-32-bits]]). The lowering's own
comment already noted the counter "is typed tyInteger"; that is precisely the
defect. The neighbouring
[[bug-nilpy-range-over-a-variant-bound-loops-forever]] is the same family — a
range bound that does not fit what the counter assumes — fixed for variants,
missed for width.

## Fix

Allocate the counter (and the comprehension's hidden loop name) `tyInt64`. A
NilPy `int` is a 64-bit cell everywhere else: the `x: int` annotation, class
fields, and every inferred local.

## Verified

| case | after |
| --- | --- |
| `range(3000000000, 3000000003)` | yields 3000000000..3000000002, then `done` |
| `range(2147483646, 2147483650)` | 4 iterations |
| `list(range(…))` / `len(range(…))` | unchanged, still correct |
| small ranges, nested loops, comprehensions | unchanged |

`test/test_nilpy_int_promotion_default.npy` extended with the large-range loop,
the 2^31-straddling count and the `list(range(...))` control; all 45 lines diff
clean against CPython. `tools/gate.sh quick` GREEN.

## Follow-up found in the same probe, NOT fixed here

The counter's SURVIVING value after the loop is wrong, independently of width —
filed as [[bug-nilpy-for-range-counter-survives-with-the-wrong-value]].

## Log

- 2026-08-06 — found, fixed and verified in one pass.
