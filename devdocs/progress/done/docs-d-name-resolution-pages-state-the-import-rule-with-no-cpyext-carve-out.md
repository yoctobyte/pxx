---
track: D
prio: 45
type: docs
blocked-by: []
summary: "docs/language/name-resolution.md:47 and docs/targets/nil-python.md:260 quote the bare-import refusal message and state the rule with no carve-out. As of 2026-08-20 a unit declaring {$PYEXTENSION} and binding the cpyext runtime IS bare-importable, so both pages are now wrong in the direction that makes a working program look unsupported."
status: done
owner: frankD
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

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Both pages carry the carve-out as an **addition**; the rule itself is untouched, and
the refusal message is still quoted verbatim on both.

- `docs/language/name-resolution.md` — new `### The one exception: a Python extension
  module`, immediately after the refusal block so the qualifier sits against the
  absolute statement. Short form: the two conditions, the declaration-vs-check split,
  the anti-widening sentence, and "nothing in the name is a signal". Links to the
  NilPy page's anchor.
- `docs/targets/nil-python.md` — the paragraph that says "a bare import name means
  Python" now carries a parenthetical pointing at the exception, and a new
  `### Python extension modules import bare` before the `-Fu` section covers it
  properly: why the rule does not apply (a Python module whose body is Pascal + C,
  as `_socket` is to CPython), a worked `import fmt_ext` example, the `{$PYEXTENSION}`
  + `pyruntime.c` unit shape, and the two negative facts the ticket asked for —
  `_ext` measured at 0 of 147, and `PyInit_<name>` not used, with the vendored-shim
  reason (`PyInit__speedups`, not `PyInit_markupsafe_ext`).

No other page in `docs/**` states the rule; `grep` found only the two the ticket
named, and `docs/**` had no prior mention of cpyext at all, so this is the first
public description of extension modules.

### Wording verified against the implementation, not the ticket summary

As instructed. The shipped criterion is `PyUnitDeclaresExtensionModule`
(`compiler/pasparser_proc.inc:3035`): a lone `{$PYEXTENSION}` line **and**
`pyruntime.c` present in the unit source — *not* the `PyInit_<name>` the decision
ratified, which the implementer measured at 3 of 6 and substituted. The pages
document what the compiler does.

### Pin boundary: closed, not waited on

The ticket warned the carve-out was unpinned. It is pinned now — `pinned` is **v391**
and `strings` finds the directive in it — so the examples are live, not deferred.

### Measured (pinned v391, no rebuild)

- positive: `test_cpyext_errformat.npy` compiles and runs on its **bare** import;
- negative: `test_nilpy_pyextension_declaration_required.npy` still refused, with the
  exact message the pages quote;
- the doc snippet itself: `import fmt_ext` / `print(fmt_ext.fmtUnicode())` compiles
  and prints `fmt=[keyname][5]`;
- the Pascal excerpt's comment inside a `uses` clause parses (checked separately —
  the real unit has no comment there, so the excerpt is not covered by the unit
  compiling).

### Filed, not decided here

[[decide-is-binds-the-cpyext-runtime-the-ratified-extension-module-check]] — the
substituted verifier was flagged "for the owner to overrule" inside a `done/` ticket
nine days ago and has had no reader. It is now pinned *and* public, so the paperwork
is worth one line of the owner's attention. Track D documented current behaviour
either way; the ticket is about ratification, and it does not block these pages.
