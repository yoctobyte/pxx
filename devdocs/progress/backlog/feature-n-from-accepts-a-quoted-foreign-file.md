---
track: N
prio: 45
type: feature
blocked-by: []
summary: "`from 'basehook.pas' import ConfigBase` and `from 'basehook.pas' as bh import X, Y` are refused with \"expected a module name after from\", while `import 'basehook.pas' as bh` works. Both from-arms test tkIdent and never consider tkString. The semantics already exist — from-import discards its name list and importing a unit opens its namespace flat — so this is a parser change with no new resolution path."
status: backlog
owner: unassigned
---

# `from` should accept a quoted foreign file

- **Track N** (NilPy frontend — `compiler/pyparser.inc` only).
- Implements [[decide-should-from-accept-a-quoted-foreign-file]], answered by
  the user 2026-08-21. That ticket holds the reasoning; this is the work.

## What to accept

```python
from 'basehook.pas' import ConfigBase          # symmetric with `import '...'`
from 'basehook.pas' as bh import X, Y, Z       # the aliased form
```

The aliased form is the one the user named, and it is the better shape: the
quoted string names a FILE, `as` turns it into a MODULE name, and `from` then
has the module it was always asking for. It is a NilPy extension (CPython has no
`from X as Y import ...`) — allowed, because NilPy is upward compatible with
CPython and accepting a form CPython rejects is a feature, not a defect.

## Where

Two sites, both in `pyparser.inc`, both currently:

    if CurTok.Kind <> tkIdent then
      Error('Nil Python: expected a module name after from');
    impName := PyConsumeDottedModule(impRoot);

at **:33393** (`PyParseOneImport`) and **:33520** (`PyParseImportRun`). Add a
`tkString` branch calling `PyConsumeQuotedModule(impKey)` + `PyImportLang` +
`PyParseImportUnitAs(impName, impLang)` — the exact sequence the PLAIN import
path already runs about 20 lines below the first site (:33417-:33427), including
the `PyImportPending` bracketing. Then consume an optional `as <ident>` before
the `tkUses` check, and fall through to the existing name-list skip loop.

## Why there is no semantic work

Both measured 2026-08-21:

- **The name list is already discarded.** After `PyParseImportUnit`, the arm
  walks the names doing nothing but `Next` and skipping `as` clauses. No binding
  step exists, so none has to be written for the quoted form either.
- **A unit's namespace is already opened flat by importing it.**
  `test/test_nilpy_subclass_unit_base.npy` asserts exactly this today with
  `class Plain(ConfigBase)` — unqualified — after `import 'basehook.pas' as
  basehook`.

So the accepted statement is semantically identical to an `import '...' as ...`
that the compiler already handles, plus a list it already ignores.

## Restore the lost assertion

`test/test_nilpy_subclass_unit_base.npy` asserted three things; the middle one
was `from basehook import ConfigBase` and was removed when the bare-import chain
to `.pas` closed. Its header records what went and why. Bring it back in the
quoted spelling — and, since the user named it, add the aliased spelling as a
fourth assertion in the same file.

## Also record the divergence

`from 'x.pas' import A` opens the WHOLE unit, not just `A`, because the name
list is discarded. Laxer than CPython, and a feature under the N-track rule (no
CPython-accepted program is broken by extra names being visible). Add it to
`devdocs/dev/nilpy-semantics-divergences.md` as part of this ticket.

Not in scope: whether an imported unit's name SHADOWS a program's own same-named
binding. That is a pre-existing property of plain `import`, not introduced here.
File it separately if the unit turns out to win.

## Gate

Track N's: `make test-nilpy` is NOT the dev loop — `make compiler/pascal26` +
self-host fixedpoint + `tools/gate.sh quick`, then push and let Track T sweep.
The restored assertions in `test_nilpy_subclass_unit_base.npy` are the repro.
