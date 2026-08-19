---
track: U
prio: 45
type: decide
blocked-by: []
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
