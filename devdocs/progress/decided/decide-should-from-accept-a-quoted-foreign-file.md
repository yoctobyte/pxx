---
track: U
prio: 45
type: decide
blocked-by: []
status: decided
owner: user
summary: "A bare NilPy import resolves to Python only, and the escape is `import 'x.pas' as x`. There is no matching escape for `from x import Name` -- `from 'x.pas' import Name` is refused with \"expected a module name after from\". Decide whether the quoted form should be accepted after `from`, or whether the alias form is deliberately the only door. A test already lost an assertion to this."
---

# Should `from` accept a quoted foreign file?

- **Type:** decide (Track U). Residue of
  `decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit` (user, 2026-08-19),
  surfaced while triaging `regression-cascade-4e27dc2be114`.

## The fork

`e1109d7bc` closed the `.pas` chain to a bare NilPy `import`, and gave it an
escape hatch — name the file with its extension:

```python
import 'tkinter.pas' as tk        # works
```

`from` got no such hatch:

```python
from 'basehook.pas' import ConfigBase
# pascal26: error: Nil Python: expected a module name after from
```

Measured 2026-08-19 at `5b1539fc7`. So a Pascal unit can be imported, but its
names cannot be pulled into the local namespace by the statement Python uses for
exactly that.

## Why it is a real fork and not just a missing feature

There is a defensible reading in which the alias form is **deliberately the only
door**: a foreign file is a file, `as` names it, and `from` is for modules. On
that reading nothing is missing and this ticket closes as *intended*.

There is an equally defensible reading in which the two statements should have
the same escape, because the asymmetry is invisible until you hit it and the
diagnostic ("expected a module name after from") describes a parse failure rather
than a policy.

Not decidable from the code — it is a call about what the spelling means.

## Options

1. **Accept `from '<file>' import a, b`**, same resolution as `import '<file>'`.
   Symmetric; every escape works in both statements. Cost: a Track A/P parser
   change in the `from` path, which already has three separate arms.
2. **Refuse it deliberately, with a diagnostic that says so** — e.g. *a quoted
   file is imported with `import '<file>' as <name>`; `from` takes a module
   name*. Cheapest, and turns an accidental silence into a stated rule.
3. **Leave as is.** The parse error stands and each person rediscovers the rule.

Recommendation: **2 at minimum, and 1 if the parser arm is cheap.** Option 3 is
the only one that is clearly wrong — the current message describes the wrong
problem, which is what made this cost a triage cycle to find.

## There is a test to restore

`test/test_nilpy_subclass_unit_base.npy` asserted three things; the middle one
was `from basehook import ConfigBase` and it is now gone. Its header records
what went and why. If this resolves as option 1, that assertion should come back
in the quoted spelling.

## ANSWER (user, 2026-08-21)

**Option 1 — accept the quoted file after `from`, in BOTH spellings:**

```python
from 'basehook.pas' import ConfigBase              # symmetric with import
from 'basehook.pas' as bh import ConfigBase        # the aliased form (user)
```

Implementation: [[feature-n-from-accepts-a-quoted-foreign-file]].

### The aliased form is the better answer to this ticket's own fork

The ticket said there was a defensible reading in which the alias form is
deliberately the only door — *"a foreign file is a file, `as` names it, and
`from` is for modules."* `from 'a.pas' as abc import x, y, z` satisfies that
reading rather than overriding it: the quoted string names a FILE, `as` turns it
into a MODULE name, and `from` then has exactly the module it wanted. It is a
NilPy extension (CPython has no `from X as Y import ...`), which is fine —
NilPy is upward compatible with CPython, and accepting a spelling CPython
rejects is a language feature, not a defect.

### Why option 1 is cheap: the feature already works, only the spelling is refused

Measured 2026-08-21 (static read + a run against the pinned binary):

- **`from X import a, b` already discards the name list.** The parser calls
  `PyParseImportUnit(impName)` to pull the whole unit in, then walks the names
  doing nothing but `Next` and skipping `as` clauses. There is no binding step
  to write.
- **Importing a unit already opens its namespace flat.** The surviving
  assertion in `test/test_nilpy_subclass_unit_base.npy` is `class
  Plain(ConfigBase)` — unqualified — after `import 'basehook.pas' as basehook`.
  Its header states the rule: *"importing the unit opens its namespace, so the
  bare class name resolves too."*

So `from 'basehook.pas' import ConfigBase` is **semantically identical to what
that test already does**, plus a discarded name list. Measured at the pinned
binary:

    from 'basehook.pas' import ConfigBase        -> error: expected a module name after from
    from 'basehook.pas' as bh import ConfigBase  -> error: expected a module name after from
    import 'basehook.pas' as bh                  -> compiles and runs

Both `from` spellings fail at the same site for the same reason: the arm tests
`CurTok.Kind <> tkIdent` and never considers `tkString`.

### Divergence to record, not to fix

Because the name list is discarded, `from 'x.pas' import A` opens the WHOLE
unit, not just `A` — laxer than CPython. Per the N-track rule that is a feature:
no CPython-accepted program is broken by extra names being visible. Belongs in
`devdocs/dev/nilpy-semantics-divergences.md`.

The one shape that could bite is a program with its own `b` importing a unit
that also defines `b`. Whichever wins, that is a **pre-existing** property of
plain `import`, not introduced by this spelling — file a shadowing check
separately if the unit turns out to win.
