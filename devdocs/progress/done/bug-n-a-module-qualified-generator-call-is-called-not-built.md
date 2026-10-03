---
slug: bug-n-a-module-qualified-generator-call-is-called-not-built
title: a module-qualified generator call is called, not built
summary: >
  `itertools.repeat(7)`, `itertools.count()`, `gm.g(1)` with a defaulted
  parameter left out: "no overload of g matches these arguments", while
  `from gm import g; g(1)` worked. The qualified spelling reached the ordinary
  call path and CALLED the generator's step routine. FIXED 2026-10-03
  (frankuser): the qualified arm builds the cursor (PyBuildGeneratorValue) like
  the bare arm does. The same day `from M import gen as alias; alias(1)` --
  which segfaulted, calling the step through a function value -- was routed
  the same way (PyImportAliasGenProc).
track: N
type: bug
prio: 40
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

    # gm.py
    def g(a, b=None):
        yield a
        yield b
    # main
    import gm
    print(list(gm.g(1)))          # pxx at pin v452: no overload of g matches
    x = gm.g(5); print(next(x))   # (assignment position, same failure)

and

    from itertools import count as _count
    c = _count(1); print(next(c))  # segfault once count became a real generator

The alias desugars to `_count = count`, a variable holding the step routine's
address, so the call passed the user's argument where the instance belongs.

## Fix

- ParseFactor's qualified-call arm: a stackless generator proc reached
  through qUnit builds a generator value.
- A from-import alias that names a stackless generator records the proc
  (PyAliasNameGen); the bare-name generator arm consults
  PyImportAliasGenProc before it gives up on a program-bound name.

Test: test/test_nilpy_mimic_itertools.npy (both import spellings) and
test/test_nilpy_classvar_counter.npy (`from itertools import count as _count`).
