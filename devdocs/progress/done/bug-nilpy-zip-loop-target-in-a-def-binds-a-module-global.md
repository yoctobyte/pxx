---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# A zip loop target inside a def binds the module global of that name

- **Type:** bug (NilPy; valid CPython → SIGSEGV) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep, one program after
  [[bug-nilpy-zip-in-a-comprehension-fails-to-parse]] unblocked it.

```python
class Vec:
    def dot(self, o):
        t = 0
        for a, b in zip(self.xs, o.xs):     # a, b are LOCALS in Python
            t = t + a * b
        return t

a = Vec([1, 2, 3])       # module names that happen to match the loop targets
b = Vec([4, 5, 6])
print(a.dot(b))          # CPython 32;  pxx SIGSEGV
```

Renaming *either* side makes it go away, which is what identifies it: the method
wrote a variant element into the module's class-typed `b` slot.

Measured with `PXXDBG=n.locals`: `Vec.dot` has locals `t` and `a` but **no
`b`** — the first target escaped only because the locals pre-pass happened to
have harvested it, so the bug presented as "the SECOND target is the broken
one", which it is not.

## Cause

`PyParseForZip` resolved its targets with `PyProgSym`, which sees module globals.
A loop target is a **binding**, and `PyAssignTargetSym` is the lookup that exists
for exactly that distinction — it reports a module global as absent inside a def
so the caller allocates a local, while still honouring `global`
(`bug-nilpy-function-local-assignment-clobbers-module-global` built it).

## Fix

Use `PyAssignTargetSym` for every loop TARGET — the zip pair, and the three in
`PyParseForIn` (single name, second name, extra names) plus the counted-range
target in `PyParseFor`. Those siblings were not visibly broken, because the
locals pre-pass usually harvests the name first, but they are the same rule
resolved with the wrong lookup and would fail wherever that pre-pass does not
reach. The augmented-assignment site keeps `PyProgSym` deliberately: `x += 1`
READS before it writes, and CPython's answer there is UnboundLocalError, not a
fresh local.

## Verified

`test/test_nilpy_loop_target_in_a_def_is_local.npy` — zip, pair-unpack,
single-name and range targets in methods, with module names colliding with every
one of them; the module bindings are asserted intact afterwards; `global count`
still writes through and a plain shadow does not. Diffs clean against CPython's
own output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit d5905f284.
