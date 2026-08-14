---
track: N
prio: 50
type: feature
blocked-by: []
summary: "Implement the decided __file__ rule: derive it from the RESOLVED executable path at run time (/proc/self/exe, not raw argv[0]) — main module = the executable itself, imported module = <exe_dir>/<basename>.py — and add sys.executable. Decision and reasoning in decide-nilpy-dunder-file-for-a-compiled-program."
status: done
owner: claude-A-N
---

# `__file__` and `sys.executable` from the resolved executable path

- **Type:** feature (frontend / runtime) — **Track N**
- **Opened:** 2026-08-13, the implementation half of
  [[decide-nilpy-dunder-file-for-a-compiled-program]], decided by the user the
  same day. Read that ticket first: it records why the compile-time source path
  was rejected (it leaks the build environment into every shipped binary) and
  why pxx follows the FREEZER convention (PyInstaller/cx_Freeze) rather than
  CPython's source convention.

## What to build

1. **Resolve the executable, do not trust `argv[0]`.** `argv[0]` can be a PATH
   lookup, a relative path, or whatever an `exec` caller chose to pass.
   `/proc/self/exe` on hosted Linux; resolve `argv[0]` against PATH/CWD on any
   target without it. One helper, used by both names below.
2. **`__file__`, main module** = that resolved executable path.
   `os.path.exists(__file__)` is then True, which is worth having.
3. **`__file__`, imported module** = `<exe_dir>/<original module basename>` —
   e.g. `/opt/app/labels.py`. A VIRTUAL path: no file is there. Deterministic,
   leaks nothing, and makes `os.path.dirname(os.path.abspath(__file__))` — the
   only form that matters in practice — the executable's directory for every
   module.
4. **`sys.executable`** = the same resolved path. Small, and it takes "where am
   I installed" off `__file__` for good.

Today `__file__` is `argv[0]` unresolved, and `sys.executable` does not exist.

## Explicitly NOT in scope

`--data-root` / a run-time base-directory override. Decided (user) to wait for
the first program that actually needs it rather than building it speculatively;
the decision ticket records the shape so it can be added without re-litigating.

## Divergence, already documented

`open(__file__)` on an imported module fails — there is no file at that path.
Frozen Python behaves the same once its temp dir is gone. The entry is already
in `devdocs/dev/nilpy-semantics-divergences.md` ("`__file__` names the
EXECUTABLE, not the source"); **check it still matches** what you land, and fix
the doc if it does not.

The user-facing half is [[docs-nilpy-file-dunder-and-data-files]] (Track D),
blocked on this ticket. Unblock it when this lands.

## Gate

A `.npy` that prints `__file__`, `dirname(abspath(__file__))` and
`sys.executable` for the main module AND for an imported sibling module, **run
from a different directory than the one it was compiled in** — that last part is
the whole point, and it is what the existing corpus habit hides (see the
decision ticket's note on why this took until 2026-08-13 to surface). Plus
`test-nilpy` green and the self-host fixedpoint.

Worth checking in the same pass: any other place the frontend answers a
"where am I" question from an unresolved `argv[0]`.

## Log
- 2026-08-14 — resolved, commit 5a71fe0be.
