---
prio: 50  # auto — blocks the portable-userland demo; also the main gap to NilPy being "real"
---

# NilPy: list / dict + string methods (split/join/strip)

- **Type:** feature (frontend — Nil-Python) — **Track A** (shared frontend +
  RTL: `compiler/pyparser.inc` / `pylexer.inc`, managed-collection RTL). Nil-Python
  has no dedicated track letter; it obeys A's self-host gate like the Pascal
  frontend.
- **Status:** backlog — filed 2026-07-10.
- **Opened:** 2026-07-10 (portable-userland demo scoping).
- **Owner:** —

## Why
NilPy today has classes, control flow (`for`/`while`/`if`/`elif`), `and/or/not/
in/is`, `str`, auto-typing (numeric widen), and C-import binding (`import sqlite`)
— proven, but thin. The three features below are what every non-trivial program
(starting with the [[feature-demo-portable-userland]] shell: argv, env, command
parsing) hits immediately, and the main thing standing between NilPy and "a real
language."

## Scope
- **`list`** — literal `[...]`, index, `append`, `len`, iterate. Maps to a managed
  dynamic array. (argv, job table, pipeline stages.)
- **`dict`** — literal `{...}`, `d[k]`, `in`, iterate keys. Maps to a managed
  hash/assoc structure. (env vars, builtin table.)
- **string methods** — `split`, `join`, `strip`, and the handful the shell needs
  (`startswith`, `find`). `str` exists; add the method surface.

Lower these onto the **existing shared IR + managed-aggregate RTL** where
possible (dynarray/managed-string machinery already exists for Pascal/C) — the
frontend work is parsing + method dispatch, not new IR primitives. A genuinely
new shared primitive (if one is needed) is a normal Track A core change, filed as
such.

## Gate
`make test` + self-host byte-identical (shared frontend/RTL). NilPy `.npy` test
programs for each feature (mirror the existing `test/test_nilpy_*.npy` set); the
[[feature-demo-portable-userland]] shell exercises them end-to-end. Land only
green.

## Links
Blocks [[feature-demo-portable-userland]] · [[project_nil_python_arc]] ·
[[project_nilpy_c_binding_arc]].
