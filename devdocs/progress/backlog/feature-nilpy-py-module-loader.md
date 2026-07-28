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
