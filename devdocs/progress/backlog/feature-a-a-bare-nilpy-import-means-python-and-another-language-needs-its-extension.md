---
track: A
prio: 60
type: feature
blocked-by: []
summary: "DECIDED 2026-08-19. A bare NilPy import resolves to Python only (.py/.npy); another language needs an explicit extension (math.pas, math.c); a residual collision is solved by `import ... as ...`. Two whitelists carry it: the language-extension set, and the lib/rtl units that ARE a Python module (re, io, math, json, random). Fixes `from classes import Foo` failing with a message about `Delete` inside a Pascal unit the program never mentioned."
---

# A bare NilPy import means Python; another language needs its extension

**Implements [[decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit]], decided by the
user 2026-08-19.** Filed as work because a decided ticket that is never re-filed is invisible
to `ready`/`next` and gets rediscovered — read the decision ticket before this one; it
carries the scope finding and both whitelists.

**Track A, not N:** the resolution machinery is in the shared `parser.inc`
(`ParseUsesUnit`, the `mimic_` prefix path at ~33743/34554/34576) and `lexer.inc`, so this is
shared-internals ground even though the semantics are NilPy's. Obeys A's gate and the
no-concurrent-edit rule with P.

## The rule

1. **A bare, extensionless import is PYTHON** — `.py` or `.npy` only.
2. **Another language needs an explicit extension** — `math.pas`, `math.c`. This is what
   makes a Pascal or C unit reachable from NilPy at all, and it is the escape hatch that
   made this preferable to simply refusing the collision.
3. **`import ... as ...` resolves a residual collision** — importing both `math.pas` and
   `math.c` leaves `math.xyz` ambiguous; the alias answers it. No new syntax.

## The two whitelists

- **Language extensions:** `pas`, `c` (later `zig`, `rs`). A trailing dotted component in
  this set selects a language; anything else stays a Python submodule, so `import xml.dom`
  is unaffected.
- **`lib/rtl` units that ARE a Python module:** `re`, `io`, `math`, `json`, `random` —
  reachable by bare name. `classes`, `types`, `strings` are NOT on it and become unreachable
  by bare import, which is the bug being fixed.

**Do not rename the whitelisted units into `mimic_*`.** The user chose a list over a rename
specifically so the 21 existing `.npy` tests that import these names do not churn.

## What this fixes

    from classes import Foo
    -> error: no overload of Delete matches these arguments

A message naming a symbol inside a Pascal unit the program never mentioned, with no path
back to the import. Also `from types import ModuleType`, which binds to `lib/rtl/types.pas`
and fails one token right.

## Acceptance

- The three population-2 names (`classes`, `types`, `strings`) refuse a bare import with a
  message naming the collision and the extension spelling that would reach the Pascal unit.
- **The 21 `.npy` tests importing `math`/`re`/`json`/`io`/`random` pass unchanged.** A test
  rewrite is correct for the population-2 shape and is a REGRESSION if applied here.
- `import math.pas` reaches the Pascal unit; `import xml.dom` still means the submodule.
- The whitelist's definition site says that adding a new Python-serving unit to the list is
  part of writing it — otherwise a bare import silently stops resolving, far from the cause.

## Gate

Track A's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. NilPy is paused
under the backlog-shrink push, so schedule this when the pause lifts or when A's queue
reaches it — the decision is recorded either way.

## Log
- 2026-08-19 — filed from the user's decision.
