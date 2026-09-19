---
slug: bug-n-sys-exit-is-a-halt-so-no-handler-sees-it
track: N
type: bug
prio: 35
status: backlog
owner: ""
created: 2026-09-19
found-by: frankH
tags: [nilpy, sys, exceptions, systemexit]
blocked-by: []
summary: "sys.exit lowers to pylib's pysys_exit, which ends the process with Halt, so a SystemExit never exists: `except SystemExit`, `finally` and `with` exit handlers do not run on an exit. The exit STATUS and the printed message follow CPython since 2026-09-19. Making it a raise needs two things beside it: NilPy's SystemExit derives from Exception (CPython: BaseException, so that `except Exception:` does not swallow an exit), and an UNCAUGHT SystemExit must exit with its status and print nothing else, where today's unhandled-exception path is emitted per backend and prints `Unhandled exception:`."
---

# Measured 2026-09-19

```python
import sys
try:
    sys.exit(3)
except SystemExit as e:
    print("caught", e.code)
print("end")
```

CPython prints `caught 3` and `end` and exits 0. NilPy exits 3 at the
`sys.exit` and prints nothing, so the `except` never runs. A `finally:` around
it does not run either.

# What is already right

`pysys_exit` takes a Variant and follows CPython's status rules: no argument
or None exits 0, an int exits with it mod 256, a bool exits 0/1, and anything
else is printed to stderr and exits 1.
test/test_nilpy_sys_exit_status_follows_cpython.npy pins that, one process per
case. Before 2026-09-19 the parameter was an Integer, so `sys.exit("msg")`
exited silently with the string pointer's low byte as the status.

# Why it is not one line

1. `SystemExit = class(Exception)` in pylib. Raising it would make every
   `except Exception:` catch an exit, which CPython deliberately does not do
   (it is a BaseException). The hierarchy needs a BaseException level first.
2. Nothing handles an uncaught one. The unhandled path is machine code emitted
   per backend in exception_emit.inc (x64, i386, aarch64, arm32, riscv, wasm),
   and it prints `Unhandled exception: <class>: <msg>` then exits with
   EXITCODE_UNHANDLED_EXCEPTION. A NilPy main program could instead be wrapped
   by the frontend in an `except SystemExit`, which exits with its code: one
   frontend change instead of six backend ones.

# Who meets it

Test harnesses and argparse callers that catch the exit.
test/test_nilpy_argparse_tsp_surface runs one process per case for exactly
this reason. That Space Program only exits, so it does not need this.
