---
track: A
prio: 60
type: bug
blocked-by: []
summary: "A promotable-int local whose value SURVIVES a yield is checkpointed as 32 bits on i386 and arm32: 6000000042 comes back as 1705032746 (exactly minus 2^32). The same arithmetic at module scope, and inside an ordinary function, is correct on both targets, so it is the generator instance's state save/restore, not the arithmetic. aarch64 and x86-64 are correct. Identical on pin v403 and at HEAD."
status: open
---

# A promo-int local in a generator truncates to 32 bits on i386 and arm32

- **Track A.** Measured 2026-09-04 by frankb-78 while writing the guard for
  `bug-a-a-managed-local-that-survives-a-yield-is-released-at-every-yield-on-every-cross-target`.
  Found because the first draft of that test carried a promo-int local and the
  row stayed red after that fix, for this unrelated reason.

## The repro

```python
def gen(k):
    n = 0
    i = 0
    while i < k:
        n = n + i * 1000000007
        yield n
        i = i + 1

for v in gen(6):
    print(v)
```

| | 4th value | 5th | 6th |
| --- | --- | --- | --- |
| CPython / x86-64 / aarch64 | 6000000042 | 10000000070 | 15000000105 |
| i386, arm32 | **1705032746** | 5705032774 | 6410065513 |

`6000000042 - 2^32 = 1705032746` exactly, and the first value to exceed 2^32 is
the first one wrong. The truncation is not cumulative in the obvious way — the
5th and 6th are each computed from a truncated predecessor.

## Where it is NOT

- **Not the arithmetic.** The identical loop at module scope prints all six
  values correctly on i386 and arm32 (verified both at HEAD and on pin v403).
- **Not the release path.** Reproduces unchanged on pin v403, which predates
  every scope-exit change of 2026-09-04.
- **Not 32-bit targets as a class.** It is i386 and arm32; aarch64 is correct,
  and riscv32/xtensa cannot run NilPy at all
  (`bug-a-nilpy-on-cross-targets-four-remaining-walls`).

So the suspect is the generator instance's checkpoint/restore of a promotable-int
local: a promo slot is a machine word plus a tier, and a 32-bit target that saves
or restores only the word loses exactly the heap tier — which is the observable.

## The guard this needs

The repro above, wired on i386, arm32, aarch64 and x86-64 with CPython's output
as the expectation. **Do not fold it into the managed-local yield test** — that
one deliberately carries no promo-int local for exactly this reason, and its
comment says so.
