---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankb-12 (v451, module-form ESP rows); routed by frankuser; fixed by frankD
tags: [nilpy, parser, import, module]
summary: "Simple statements separated by ';' at the top level of an IMPORTED module (`a = 1; b = 2`, `s += 1; s -= 2`, `f(); print(2)`) failed with `expected expression` on every target. The same lines parsed as a main program and inside any indented block. The module's top-level loop parsed one statement per line and never consumed the ';'. It now loops over them the way the program loop and PyParseBlock do."
owner: ""
---

# ';'-separated statements fail at an imported module's top level

```python
# scmod.py
a = 1; b = 2          # pascal26:1: error: expected expression
# scmain.npy
import scmod
print(scmod.a + scmod.b)   # CPython: 3
```

## Cause and fix

pyparser.inc has three statement loops:

- the program loop;
- PyParseBlock, for every indented suite;
- the imported module's top-level loop.

The first two consume `;` and parse the next simple statement on the same
line. The module loop parsed one statement and then returned to its line
loop, where the `;` began a statement and failed. The module loop's
ordinary-statement arm now repeats while a `;` follows, and stops at a
trailing `;`, as the other two loops do.

## Measured (2026-09-29, fixedpoint 14a778a7c574)

- `test/test_nilpy_semicolons_at_an_imported_modules_top_level.npy`, with its
  module `test/semimod.py`, covers:
  - assignments and augmented assignments;
  - calls;
  - a trailing `;`;
  - a one-line `if` suite and a one-line `for` suite;
  - a string after the `;`.

  It equals CPython on x86-64, i386, riscv32, arm32 and wasm32. With the
  previous compiler, it does not build on any of them. The rows are x86-64,
  i386 and wasm32.
- `test_nilpy_chained_assign_nested_attr`, `test_nilpy_chained_assign_powassign`
  and `test_nilpy_suites`, compiled as an imported module under a one-line
  `import` main, now equal CPython on x86-64. With the previous compiler, all
  three failed to build.

## Not covered: a separate defect

`class P:` with `k = 1; j = 2` in its body fails with `class method not found: j`
in a main program as well, so it is not this loop. Its cause was not
investigated here, and it was reported to the coordinator.
