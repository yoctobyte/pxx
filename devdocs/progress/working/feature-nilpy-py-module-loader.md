---
track: N
prio: 55
type: feature
---

# NilPy: `import <sibling>.py` — compile a real Python module as a unit

The one thing standing between six working songformatter files and one program.
Two modules of the app now compile AND run on their own (`key_analysis.py`,
`settings.py`), and every remaining module starts by importing them:

```python
from settings import get, set, getF, getI      # convertrawtext.py
from key_analysis import analyze_key           # convertrawtext.py
import key_analysis                            # kadrv.py
```

## What happens today (probed 2026-07-28, compiler at afe03074)

```
pascal26:1: error: uses: unit source not found: helper
```

NilPy turns `import X` into a Pascal `uses X` at LEX time (`pylexer.inc`), and
the unit resolver (`parser.inc`, the `ParseUsesUnit` search chain) looks for
`X.pas` / `X.pp` — plus `.c` / `.h` for the C frontend. A sibling `X.py` is not
in the chain, so both `import helper` and `from helper import add` fail on line
1. That is the whole gap: the mechanism for pulling foreign source into the same
ELF already exists and is proven (a sibling `.c` compiles in statically —
`cparser.inc:8120`, `test/test_c_import.pas`).

## Shape

1. **Resolution** — extend the chain with `X.py` / `X.npy`, only when the
   importer is NilPy (a Pascal program must not start importing Python
   accidentally).
2. **Module parse** — parse the file with the NilPy frontend in MODULE mode: its
   defs and classes register as unit-level procs/classes; its module-level
   statements become the unit's initialisation, run once before the importer's
   own body. songformatter needs exactly this: `settings.py` runs
   `ensure_default_settings()` at import time and the importer depends on it.
3. **Namespacing** — `import X` must give qualified access (`X.f()`), `import X
   as Y` the alias (the resolver's `uses ... as` already does aliases), and
   `from X import a, b` must bind the individual names. A module-level NAME
   (`settings.cfg`, `key_analysis.MODAL_KEYS`) has to be reachable too, not just
   defs.
4. **Cycles and repeats** — importing the same module twice must not compile it
   twice (Python's `sys.modules` behaviour); a cycle should be a clear error
   rather than a hang.

## Watch out for

- **[[bug-nilpy-stdlib-name-binds-pascal-unit]] gets sharper**: a local
  `json.py` next to the program would now compete with `lib/rtl/json.pas`. The
  search ORDER is the policy decision — Python's is "the script's directory
  first", ours currently is the RTL's. Settle it in that ticket, not here.
- The typing pre-pass trial-parses bodies; a module compiled twice must not
  register its shells twice (the nested-def path solves the same problem with an
  idempotent shell registration — reuse that discipline).
- `from X import *` is not needed by songformatter and can wait.

## Acceptance

`convertrawtext.py` gets past its imports; a two-file probe
(`helper.py` + `main.py`, both spellings above) prints CPython's answer; and
importing a module twice runs its module-level code once.


## LANDED (2026-07-28) — and it was plumbing, not a redesign

The first framing of this ticket overstated the difficulty. Almost everything a
module loader needs already existed for Pascal units and only had to be pointed
at a `.py` file:

| need | what already did it |
| --- | --- |
| compile a foreign source into the same ELF | `ParseUsesUnit`'s C branch (a sibling `.c`), copied in shape |
| name scoping, qualified access, aliases | `CurrentUnitIdx` tagging + `uses ... as` (which is how `import X as Y` works) |
| import-time code | a unit's `initialization` section, registered in `InitProcs` |
| don't compile a module twice | `CompiledUnits` dedupe in `ParseUsesUnit` |

What was actually written:

1. **`PyLexAppend`** — lex a module onto the end of the token stream and return
   its first token, the shape `LexAppend` / `CLexAppend` already have. `PyLexAll`
   no longer resets `TokCount` when appending.
2. **`ParsePyUnit`** — the program parser's loop, with the top-level statements
   compiled into an `__init_<module>` proc registered in `InitProcs` instead of
   into the program body. They are PARSED with `CurProc = -1`, so the names they
   bind stay module-level variables rather than becoming locals of the init proc.
3. **`PyScanLo`** — the top-level pre-passes (class shells, class fields, def
   shells, imports) scanned `0 .. MainProgramTokCount`; they now scan the
   compilation unit being parsed, which for a module is its own span.
4. **Resolution** — a NilPy import looks for `X.py` / `X.npy` in the importing
   file's directory FIRST, which is Python's own rule and settles the shadowing
   question for NilPy: a local module beats the RTL, a name with no local module
   still finds `lib/rtl/X.pas` (so `import re` is unchanged).
5. **`ParsePyProgram` emits the init calls** before the program body, exactly as
   `ParseProgram` does for Pascal. Without it a module's top-level code never
   ran: module-level names read as zero and the first list access segfaulted.

Two traps: `PyRegisterClassShells` is the pass that CREATES each class row (the
field pre-pass only fills one in), so a module whose class was not shelled first
failed with "undefined variable" on its own class; and the pre-passes' bounds
guard is `MainProgramTokCount`, which has to be re-pointed at the module's end
while it parses.

Verified against CPython: module functions, classes, module-level names,
qualified and `from`-import spellings, a module importing another module, a
double import running its initialisation once, and ordering (module init before
program body). Test: `test/test_nilpy_py_module_import.npy`.

Still open, and deliberately not done here: `from X import *`, relative imports
(`from . import y`), and packages (a directory with `__init__.py`).

## Closing (2026-07-31)

Already landed and gated (`test/test_nilpy_py_module_import.npy`, in the
Makefile) — re-verified directly (`from helper import add` across a
sibling `.py`, `add(2, 3)` -> `5`, matching CPython). This ticket just
never got moved out of `backlog`/marked done despite the LANDED entry
above. The three deliberately-deferred items (`from X import *`, relative
imports, packages) remain genuinely open but are smaller, separate asks —
worth their own tickets if a corpus hits them, not reasons to keep this one
open.
