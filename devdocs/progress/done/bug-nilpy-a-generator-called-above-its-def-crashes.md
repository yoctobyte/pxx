---
track: N
prio: 65
type: bug
---

# A generator called from code written ABOVE its def crashes or loops wrong

Found 2026-10-19 while writing the slot-early regression test. It's
pre-existing: 12ddb7d995 does the same.

```python
def early():
    return list(gen(2))

def gen(n):          # also: (n, k=SCALE), (n, xs=None)
    i = 0
    while i < n:
        yield i
        i += 1

print(early())       # CPython: [0, 1]
```

pxx crashes with no output (SIGSEGV) for `gen(n)`, `gen(n, k=SCALE)` and
`gen(n, xs=None)`. With `gen(n, k=3)` it prints `[0, 1, ..., 10]`: n is read
wrong. Defining `gen` above `early` works. This looks like the generator call
or for-in desugar lowering against the shell-pass registration rather than the
real one. That was not investigated.

## Diagnosed 2026-11-10 (not fixed)

The registration is fine. The shell pass applies the generator ABI and
`PyMarkGeneratorProc`, and `PXXDBG=n.ret` agrees in both orders. The crash
comes from two numbers the CALL site bakes in that only exist once the
generator's BODY has been compiled (`PyParseDef`, the `isGenDef` arm):

- `ProcGenInstSize[gpi]` is set to `SL_OFF_SLOTS + 8 * CurGenSlotNext` after
  `AssignStacklessSlots`. `PyBuildGeneratorValueAt` emits it as an int literal
  for `SlNew`, so a caller compiled first allocates a header-only instance (size
  0 + header) and the seeds below write past it: SIGSEGV.
- `GenArgSlotOff` falls back to `SL_OFF_SLOTS + 8*(k-1)` when
  `ProcGenArgOff` is unrecorded. NilPy parameters are variants and take
  TWO-word slots, so the fallback is wrong from the second parameter on. That
  explains the `gen(n, k=3)` row, which reads n wrong rather than crashing.

Fix direction, not a reordering. Compiling generator bodies first fails on any
generator that reads a module global assigned later. Instead, give each
generator a FACTORY proc compiled right after its body, taking the declared
parameters and returning the PYITER_SLGEN cursor (SlNew + seeds +
pygen_iter_new). Every value-position call then becomes an ordinary forward
call that ApplyCallFixups resolves. The `for` desugar (ParseForInGeneratorAST)
has the same dependency and would want the same treatment, or a guard that
routes an uncompiled generator through the factory.

## Fixed 2026-11-11

The factory the diagnosis above proposes: see
bug-n-a-generator-def-nested-in-a-def-segfaults, which needed the same thing
because a nested body always compiles after its caller. All three rows above
(`gen(n)`, `gen(n, k=SCALE)`, `gen(n, xs=None)`) now match CPython, plus a
`for` over the generator, `next()`, and keyword arguments.
Test: `test/test_nilpy_a_generator_called_above_its_def.py` (row genabove26).
