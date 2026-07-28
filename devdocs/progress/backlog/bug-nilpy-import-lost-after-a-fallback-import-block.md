---
track: N
prio: 70
type: bug
---

# A C library's function name shadows a Python module name as a qualifier

Found on songformatter's `convertrawtext.py`, which is blocked by it
([[feature-demo-songformatter-pxx-target]]).

## Symptom

```
pascal26:97: error: unexpected token
  near: name     atexit >>>  register
Expected: =, but got:  (Kind: 81, Line: 97)
```

`atexit.register(del_tmp_file)` is read as an assignment target, so the parser
wants an `=`. The import is present and correct.

## Root cause

`lib/crtl/include/stdlib.h:45` declares `int atexit(void (*func)(void));`. Any C
unit pulled into the program includes `<stdlib.h>`, which registers a PROC named
`atexit` — and NilPy then resolves the bare name to that proc instead of treating
it as a unit qualifier, so the dotted form stops parsing.

In songformatter the C unit arrives through `from reportlab.pdfgen import
canvas`: the shim `lib/pcl/mimic_reportlab_pdfgen.pas` pulls the vendored
`pdfgen.c`.

## Repro, smallest form

A NilPy program, a Pascal unit `mid.pas` that does
`uses pxxcio, sysutils, '<repo>/lib/vendor/pdfgen/pdfgen.c';`, and:

```python
import mid
import atexit

def bye():
    print("bye")

atexit.register(bye)
```

Swap the shim for one with no C behind it (`from reportlab.lib.units import mm`)
and it compiles. Position does not matter — importing `atexit` BEFORE the C unit
fails the same way.

## Ruled out along the way

- Not the fallback-import handling: a `try/except ImportError` block whose try
  branch resolves, followed by the same call, compiles and runs.
- Not the submodule-alias registration (disabling it changes nothing).
- Not the `CompiledUnits` cap (raising 256 to 1024 changes nothing).

## Where the fix is NOT

`ConsumeUnitQualifier` (`compiler/parser.inc:864`) is not the site: it never
consults `FindProc`, and it would happily return the unit for `atexit`. The
shadowing therefore happens UPSTREAM, in NilPy's dispatch for a statement or
factor that starts with an identifier — the proc named `atexit` is matched there
before the qualifier is ever considered. Start by finding which branch in
`PyParseStatement` / `PyParseFactorCore` claims the name.

## Fix direction

Where NilPy decides whether a dotted name is a unit qualifier, a name that IS a
compiled unit should win over a C proc of the same name — at least in the
`name.member(` shape, which cannot be a call of the C function. The general
version of this is the same question as
[[bug-nilpy-stdlib-name-binds-pascal-unit]], now from the C side: the C library
namespace is flat too, and `time`, `math`, `random` and `signal` are all C
functions AND Python modules.

## Gate

`make test-nilpy` plus a `.npy` that imports a unit pulling a C source and then
uses `atexit.register`, and a check that a genuine C `atexit(...)` call from C
code still resolves.
