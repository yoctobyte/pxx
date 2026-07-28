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

## Narrowed to the EXPRESSION parser

Written as a value rather than a statement, the failure changes shape:

```python
x = atexit.register(bye)
```
```
pascal26:7: error: expected expression
  near:    x  atexit >>>  register
```

So it is NilPy's factor/expression path that claims the name, not the
dotted-statement branch at `pyparser.inc:8821` (that branch just calls
PyParseBoolExpr and then fails its `Expect(tkAssign)` because the expression
parse stopped early). Fix the factor path and both spellings follow.

## The unit IS loaded — only the QUALIFIER form breaks

Decisive experiment: after the C unit is pulled,

```python
from atexit import register
register(bye)          # compiles and RUNS, prints "bye" at exit
```

while `import atexit` + `atexit.register(bye)` does not parse. So the unit is
found, compiled and callable; what fails is recognising `atexit` as a qualifier.

Two candidate causes inside `ConsumeUnitQualifier` were tried and are NOT it:

- `if FindSym(name) >= 0 then Exit;` — restricting that shadow test to
  locals/params/own-unit symbols (so a C library's symbol cannot beat a unit
  name) changes nothing. Reverted.
- the `CompiledUnits` cap. Reverted.

That leaves `FindUnitOrAlias(name)` returning -1 for a unit that demonstrably
compiled — check what `FindCompiledUnit('atexit')` sees after a C pull, and
whether the C unit's registration disturbs the `CompiledUnits` / `Strs`
interning the lookup depends on. Instrumenting that lookup is the next step and
should settle it in one run.

## ConsumeUnitQualifier is never REACHED

Instrumented at the very first line of `ConsumeUnitQualifier`
(`compiler/parser.inc:864`), before every early Exit: with the C unit pulled,
the probe never fires for `atexit`. So the qualifier machinery is not choosing
wrongly — control never gets there.

`ParseFactorCore` calls it at `parser.inc:9352`, and that line is not reached
either, which means an EARLIER branch of `ParseFactorCore` (or of the NilPy
`ParseFactor` wrapper above it) claims the name first — the obvious candidate
being a branch that fires because `FindProc('atexit')` now succeeds, crtl having
declared it.

`ParseFactorCore`'s ident branch is not reached either — probed at
`parser.inc:9352`, immediately before and after the `ConsumeUnitQualifier` call,
and neither line fires. So the name is claimed BEFORE any expression parsing
begins, i.e. in NilPy's STATEMENT dispatcher, not in the factor path.

The error text places it exactly: `near: bye atexit >>> register` means the
parser consumed `atexit` AND the `.` and then rejected `register`. Something is
consuming an identifier plus a dot and then expecting a different token — and it
is not `ConsumeUnitQualifier`, which never runs.

**Leading hypothesis after all the eliminations: the failure is in a PRE-PASS,
not the body parse.** The only `ident '.'` statement branch is
`pyparser.inc:8822`, and it routes to `PyParseBoolExpr`, which would have
reached the probed line in `ParseFactorCore` — it did not. Meanwhile a NilPy
module goes through `PyRegisterDefShells` / `PyCollectModuleLocalsAST` BEFORE the
body is parsed, and those walk module-level statements with their own simplified
grammar. A pre-pass failure also outranks a body failure in reporting, which is
why the line number looks like ordinary statement parsing. Probe those two
pre-passes first; the body-parse paths are already ruled out.

**Then:** probe the top of `PyParseStatement` for a statement
whose first token is `atexit`, printing which branch takes it, and work forward
from there. The dotted-statement branch at `pyparser.inc:8821` is NOT it (it
routes to PyParseBoolExpr, which would have reached ParseFactorCore). Look for
an earlier branch that pattern-matches `ident '.'` — a class/instance member
assignment path is the likeliest shape, and it would be selected because
`FindProc('atexit')` now succeeds.

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

> Instance of [[decide-unit-local-names-leak-to-global-scope]] — unit-local
> names are visible program-wide, so the first registration wins and the answer
> depends on import order. Fixed here at the call site; the root is that ticket.

## Log
- 2026-07-28 — resolved, commit 014a9bcba.

## Resolution

Fixed by 014a9bcba ("fix(nilpy): a C library's names no longer swallow Python
ones") and 7f851b83c. The ticket was left in `backlog/` by those commits.

Re-verified 2026-07-28 on both shapes: a plain `import atexit` with
`atexit.register(...)`, and the songformatter shape where a
`try: from reportlab.pdfgen import canvas / except ImportError:` block pulls a
C unit (and with it crtl's `int atexit(void (*)(void))`) BEFORE the import.
Both compile and print `main` / `bye` in CPython's order.
