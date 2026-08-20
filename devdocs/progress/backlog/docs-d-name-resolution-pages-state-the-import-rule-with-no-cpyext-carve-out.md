---
track: D
prio: 45
type: docs
blocked-by: []
summary: "docs/language/name-resolution.md:47 and docs/targets/nil-python.md:260 quote the bare-import refusal message and state the rule with no carve-out. As of 2026-08-20 a unit declaring {$PYEXTENSION} and binding the cpyext runtime IS bare-importable, so both pages are now wrong in the direction that makes a working program look unsupported."
---

# The name-resolution docs state the NilPy import rule with no cpyext carve-out

- **Track D** — prose only. `docs/language/name-resolution.md:47`,
  `docs/targets/nil-python.md:260`.
- **Raised by** frank3 while implementing the carve-out, deliberately NOT touched: `docs/**`
  is Track D's and a frontend agent editing it would be crossing a lane for convenience.

## What changed under these pages

The owner decided ([[decide-nilpy-import-rule-vs-a-cpyext-extension-module]], 2026-08-20)
that a cpyext **extension module is not a Pascal unit** and therefore never enters the
import rule's jurisdiction — bare `import <name>` is correct for it. Implemented in
`feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit`.

Both pages currently quote the refusal message verbatim and state the rule absolutely.
They are now wrong in the **more expensive direction**: a reader with working code sees the
documentation say it is unsupported, which reads as a defect in the compiler rather than a
gap in the docs.

## What the pages should say

The rule itself is **unchanged and stays** — the owner affirmed the quoted spelling as the
consistent rule for reaching a Pascal unit, and explicitly rejected the reading that it was
a workaround. So this is an *addition*, not a correction:

- a bare NilPy import resolves to Python (`.py`/`.npy`);
- a Pascal unit is reached by naming it with its extension, `import 'unit.pas' as unit`;
- **and** a unit that declares `{$PYEXTENSION}` *and* binds the cpyext runtime is a Python
  extension module, not a Pascal unit, so it is reached by bare import exactly as CPython
  reaches `_socket`.

Do NOT document `_ext` as meaningful. It was measured and rejected: of 147 real CPython
extension modules on this box (48 stdlib `lib-dynload`, 61 statically builtin, 99
third-party `.so`), **zero** end in `_ext` and 70 begin with a leading underscore. The
`_ext` names in `test/nilpy_units/` are test-local naming.

**Verify the wording against the implementation before publishing** — the second half of the
criterion was changed during implementation (`PyInit_<name>` was falsified by real vendored
extensions, whose init symbol carries the *upstream* module's name). Read the ticket's final
state, not this ticket's summary, and do not invent behaviour.

## Gate

Docs internally consistent; any snippet compiles against `$(PXX_STABLE)`. **Note the pin
boundary:** the carve-out is at HEAD and not yet pinned, so a snippet exercising it will not
compile until the next pin. Either wait for the pin or mark the example as requiring it.
