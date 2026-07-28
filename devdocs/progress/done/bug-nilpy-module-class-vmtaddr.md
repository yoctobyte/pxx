---
track: N
prio: 60
type: bug
---

# A class in an imported `.py` module: "invalid class index in vmtaddr"

With the module loader in ([[feature-nilpy-py-module-loader]]), a small module
carrying a class imports and runs correctly, but songformatter's
`key_analysis.py` — 762 lines, several classes, dataclasses among them — fails
at the END of its own parse:

```
$ pascal26 pr5.py            # from pathlib import Path; from key_analysis import analyze_key
pascal26:763: error: invalid class index in vmtaddr
```

Line 763 is one past the module's last line, so this is emitted while the
module's own compilation is being finished rather than at a statement.

The same file compiles and RUNS as a program (that is how it was brought up —
see the umbrella ticket), so the class machinery itself is fine; what differs is
that its classes are now registered while `CurrentUnitIdx` names a unit, and
that the module's body is compiled into an `__init_<module>` proc rather than
into the program body.

Likely suspects, in the order worth checking:

1. a class row created by `PyRegisterClassShells` for the MODULE whose VMT is
   emitted against the program's class numbering;
2. the dataclass path (`PyDcCount` / `PyDcClassIsDc` are reset once per
   program in `ParsePyProgram`, not per compilation unit — a module parsed
   after the program's reset shares that state);
3. `PyMembersHoisted`, likewise reset only in `ParsePyProgram`.

## Repro

```
cp ~/songformatter/*.py /tmp/sfm/ && cd /tmp/sfm
printf 'from key_analysis import analyze_key\nprint("ok")\n' > p.py
pascal26 p.py p
```

## Gate

`make test-nilpy` with a module carrying a dataclass and a plain class used from
the importer, plus the songformatter repro above.


## FIXED (2026-07-28) — the module's FIRST import was never pre-scanned

Not a class-numbering problem at all. `PyPreScanImports` recognises a top-level
import by "the token before it ends a line, or it is token 0" — and for a MODULE
the token before its first one is whatever the program's stream ended with. So a
module whose FIRST line is an import (`import re`, which is `key_analysis.py`'s
line 1) had that import skipped by the pre-scan and compiled later, from the
BODY parse — in the middle of accumulating the module's top-level statements.

Compiling a Pascal unit resets the AST pool (`ParseSubroutine` ends with
`ASTNodeCount := INLINE_AST_RESERVE`), so every statement node collected so far
was recycled under the module's feet, and the init proc was then built from
whatever those slots held: "invalid class index in vmtaddr" from a node that had
been a list literal. The one-line fix is `(i = PyScanLo)` in place of `(i = 0)`.

Minimal repro, if it ever regresses:

```python
# lm2.py
import re
ALL = ['C', 'D']
# main
import lm2
print(lm2.ALL[1])
```
