---
track: N
prio: 45
type: bug
blocked-by: []
summary: "A failed file syscall raised FileNotFoundError for EVERY errno, with the bare path as its message, where CPython picks the subclass by errno and says `[Errno 2] No such file or directory: '<path>'`. And IOError was a SIBLING of FileNotFoundError rather than an alias of OSError, so `except IOError:` did not catch a missing file."
---

# A failed file syscall lost both its class and its message

Found 2026-08-16 while triaging Track T's `regression-cascade-343a52551808`:
the uforth corpus is diffed against CPython byte for byte, and a missing
`INCLUDE` printed the bare path.

## Measured

```python
open("/nonexistent/f.txt")
# CPython  FileNotFoundError: [Errno 2] No such file or directory: '/nonexistent/f.txt'
# NilPy    FileNotFoundError: /nonexistent/f.txt

open("/tmp", "w")
# CPython  IsADirectoryError: [Errno 21] Is a directory: '/tmp'
# NilPy    FileNotFoundError: /tmp                      <- wrong CLASS

try:
    open("/nonexistent/f.txt")
except IOError as e:      # the most common spelling of this guard
    ...
# CPython  caught
# NilPy    NOT caught
```

## Cause, both halves

1. **Class.** Every `PyPal*` failure path raised `FileNotFoundError.Create(path)`
   unconditionally. `__pxxrawsyscall` returns the raw kernel value, so the errno
   was right there in `r` and simply not read.
2. **Alias vs subclass.** `IOError = class(OSError)` makes IOError a SIBLING of
   FileNotFoundError, not an ancestor, so `except IOError:` misses it. CPython
   makes IOError and EnvironmentError *aliases* — `IOError is OSError` is True.
   pylib's own comment said "aliases of OSError" while the line below it said
   `class(OSError)`; the comment was right and the code was not.

## Fix

`pyos_raise_ioerror(err, path, path2)` in pylib maps errno → subclass and builds
CPython's message (including the `-> 'dst'` tail for two-path calls), and the
four raise sites call it. `IOError = OSError;` / `EnvironmentError = OSError;`.

## Why it matters

The message half is what a program PRINTS — nothing crashes and no value is
wrong, so only a differential corpus catches it. The class half is worse: a
program that distinguishes "not there" from "not allowed" takes the wrong
branch silently, and one that guards with `except IOError:` — which CPython
accepts and runs — does not catch at all. That is the upward-compatibility
direction that is not negotiable.

## Gate

`test/test_nilpy_oserror_class_and_message.npy`, six shapes diffed against
CPython byte for byte; the uforth `filetest` word set identical to CPython;
`gate.sh quick` green.
