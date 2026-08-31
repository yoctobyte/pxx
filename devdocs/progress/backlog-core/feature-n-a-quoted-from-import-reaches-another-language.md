---
track: A
prio: 15
type: feature
blocked-by: []
summary: "`import 'sysutils.pas' as su` works; `from 'sysutils.pas' import Trim` does not. The quoted cross-language import was built for the PLAIN arm only, because the from-arms thread impName/impRoot through member binding, alias recording and PyStdAliasRecord. Nothing needs it today — the refusal diagnostic points at the plain spelling, which works — so this is filed to be visible rather than to be urgent."
---

# A quoted `from ... import` should reach another language too

Follow-up to
[[feature-a-a-bare-nilpy-import-means-python-and-another-language-needs-its-extension]]
(landed 2026-08-19, `3284c881d` / `6fba42d69` / `e1109d7bc`). Filed because an unbuilt arm
that lives only in a resolved ticket's prose is invisible to `ready`/`next` and gets
rediscovered.

## What works and what does not

    import 'sysutils.pas' as su          ok    -> su.IntToStr(42)
    import './mymod.pas' as m            ok
    import './lib2.c' as c               ok
    from 'sysutils.pas' import Trim      NOT BUILT — "expected a module name after from"

## Why it was left out, rather than being an oversight

The plain-import arms needed one branch each: consume the string, pin the language, resolve.
The **from**-arms are a different shape — they thread `impName` and `impRoot` onward through
member binding, alias recording, `PyStdAliasRecord` and `aliasUnitTarget`, and `impRoot` in
particular is fed to the consumed-only predicates. Handing them a quoted target means
deciding what each of those does with a name that is a path or carries an extension, which is
real work rather than three more lines. Note the live trap: `PyImportRootPlainIsConsumedOnly`
matches on the root, so a naive `import 'random.pas'` that set `impRoot` to `random` would be
silently SKIPPED. The plain arm avoids this by never routing a quoted import through the
consumed-only check at all.

## Why it is low priority

The refusal diagnostic that motivates the whole feature points users at the **plain**
spelling, which works:

    from classes import Foo
    -> ... To reach the Pascal unit, name it with its extension: import 'classes.pas' as classes

So there is a working answer for every case the rule refuses, and `import 'x.pas' as x`
followed by `x.Sym` covers what `from 'x.pas' import Sym` would give. Raise the priority when
a real file wants the from-spelling — not before.

## Acceptance

- `from 'sysutils.pas' import Trim` binds `Trim` unqualified, as the unquoted from-import
  does for a resolvable unit.
- `import 'random.pas'` is NOT swallowed by the consumed-only root rule (the trap above).
- The plain quoted form and every unquoted import are unchanged — A/B against the pin.

## Gate

Track A's: `make compiler/pascal26` + `tools/gate.sh quick`, plus `test_nilpy_quoted_import`.
