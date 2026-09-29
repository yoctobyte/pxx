---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, while writing from X import *); asked for by frankuser for MicroPython's `from machine import *`
tags: [nilpy, import, stdlib, esp]
summary: "`from random import *`, `from sys import *`, `from os import *` and `from os.path import *` bound nothing the compiler's call table provides: `seed(1)`, `argv` and `getcwd()` were each \"undefined variable\". They now bind every public member the table provides for that root. A later def or assignment in the module wins, as in CPython, and another module is not touched. `from machine import *` and `from time import *` already worked (Pascal shim units, flat scope); a C3 build row and a QEMU run now pin that."
owner: ""
---

# `from X import *` does not bind call-table members

```python
from random import *
seed(1)            # before: undefined variable (seed)
```

## Fix (compiler/pyparser.inc)

- `PyStdStarRecord(root)` remembers each star-imported root per
  importing unit. Both from-import arms call it: the consumed-only one
  (sys, os, os.path) and the unit one (random has a unit and table
  members).
- `PyStdAliasLookup` falls back to the star roots after the explicit
  aliases. A bare name binds if a star root of this unit
  `PyStdProvidesMember`s it. That is the same membership test
  `from sys import argv` uses, so the explicit and star forms cannot
  disagree, and nothing enumerates the table. The shadowing test is the
  explicit form's: a def bound here or a module variable wins. Names
  starting with `_` are not bound. The call-table roots define no
  `__all__`, so CPython's rule is public names.
- Its early exit tested only the explicit table's count, so the star
  table was never consulted until that was fixed.

## Against CPython

For every root in PyStdlibCallProc, CPython's `from <root> import *`
binds every member the table maps, except `os.startfile` (Windows-only;
here it binds but CPython on Linux has no such name).

## Shim modules

`machine` and `time` are Pascal units under lib/rtl/platform/esp and
lib/rtl, so a star import already reached their names through flat unit
scope. A Pascal unit has no `__all__`. A `.py` shim goes through
PyStarImportRecord, which honours `__all__`.

## Rows

- test/test_nilpy_from_import_star_of_a_compiler_provided_module.npy, with
  test/starmod_randint_own.py and .expected from CPython. It covers
  random, sys, os and os.path members, a later def and a later
  assignment winning, and an imported module keeping its own `randint`.
  x64 (fromstarct26); red before the fix.
- test/esp_from_machine_import_star.npy: an ESP32-C3 build-only row
  (riscv32, --platform=esp). It also builds on the compiler before this
  fix, so it guards the idiom rather than this change. Under QEMU
  (tools/esp_run.sh --chip esp32c3, ESP_RUN_PROJECT=nilpy-hw-c3) it prints
  `0 True`, the same as the qualified spelling.
