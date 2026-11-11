---
slug: bug-n-a-generator-def-nested-in-a-def-segfaults
title: a generator def nested in a def segfaults on its first call
track: N
type: bug
prio: 70
status: done
---

## Repro (latest-ba3b84f1a2 and earlier)

```python
def gen():
    def g(n):
        for i in range(n):
            yield str(i)
    return list(g(5))      # also: for s in g(5), sum(g(5))
print(gen())               # CPython: ['0', '1', '2', '3', '4']   pxx: SIGSEGV
```

A module-level generator worked. Found by the same leak probe as
bug-n-a-repr-dunder-taken-as-a-value-segfaults-repr.

## Cause, three layers

1. PyQueueNestedDef registered the nested def as a plain routine, while its
   body (PyParseDef at the drain) was compiled as a stackless step function.
   The enclosing body's `g(5)` was an ordinary call into a state machine.
2. With the ABI applied, the bare-name generator arm still looked the name up
   unqualified (`g`) while a nested def registers as `gen.g`.
3. A nested body is compiled after its enclosing body, so the call site always
   meets a generator whose instance size and slot offsets do not exist yet.
   That is bug-nilpy-a-generator-called-above-its-def-crashes in another shape,
   and it is fixed the way that ticket proposed: a factory proc per generator.

## Fix

- PyQueueNestedDef applies PyApplyGeneratorABI and PyMarkGeneratorProc. The
  captured enclosing locals append after the declared parameters and count in
  ProcGenParamCnt.
- The generator value arm resolves through PyQualifyNested.
- PyBuildGeneratorValueAt parses the arguments (positional, then keyword by
  parameter name, then defaults, then captures). It builds the cursor inline
  when the body is compiled. Otherwise it calls `$pygenmk_<gpi>`
  (PyGenFactoryFor), which returns the same TPyIter. Its body is
  PyGenValueFromArgs over its own parameters, compiled by PyDrainGenFactories
  at the end of the program and of each module.
- The `for` desugar takes its inline path only for a compiled generator. An
  uncompiled one iterates the factory's cursor.

Keyword arguments to a generator call were refused before (`gen(3, k=2)` said
"undefined variable (k)") and now bind by name.

Test: `test/test_nilpy_a_generator_nested_in_a_def.py` (row gennest26). All 57
existing generator tests with an `.expected` pass, including
test_nilpy_a_generator_outlives_its_caller_and_its_arguments under
-dPXX_HEAP_DEBUG. A 3000-call RSS probe through both the nested and the
factory path reads 0 bytes per call.
