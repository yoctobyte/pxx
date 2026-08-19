---
track: A
prio: 70
type: bug
blocked-by: []
summary: "lib/pcl/tkinter.pas was written so that `import tkinter` resolves by bare name -- its own header says so -- but PyRtlUnitServesPython does not list it, so every real tkinter program is refused at its first line. Six examples/tk/*.npy went red at e1109d7bc. Verified fix: one name added to the list; no test or example edit."
status: done
owner: frank3
---

# `tkinter` is missing from the Python-serving unit list

- **Type:** bug (Track A — `compiler/parser.inc`, the NilPy import resolver).
  Falls out of `regression-cascade-4e27dc2be114`; filed rather than fixed
  because it edits the shared `parser.inc` and frank3 holds the A/P slot.
- **Found:** 2026-08-19, triaging the cascade.

## What is wrong

`e1109d7bc feat(A,N): a bare NilPy import resolves to Python, not a Pascal unit`
closes the `.pas` chain to a bare NilPy `import`, except for the units named in
`PyRtlUnitServesPython` (`compiler/parser.inc`) — the curated list of units that
ARE the Python module of that name. `tkinter` is not in it.

It should be. `lib/pcl/tkinter.pas`'s own header states the property as a design
decision, and names two units that ARE on the list in the same sentence:

> Named `tkinter` so `import tkinter` resolves through the unit resolver, like
> lib/rtl/re.pas and configparser.pas.

So this is not a unit that "happens to share a Python name" — the exclusion the
list's design note is written around (`classes`, `types`, `strings`). It is the
inclusion case, missed because it lives in `lib/pcl` while the list was built by
sweeping `lib/rtl`. The note anticipated exactly this failure:

> ADDING A UNIT TO THIS LIST IS PART OF WRITING ONE. [...] the failure lands at
> the import of a unit that plainly exists, far from the omission that caused it.

## Repro (any of the six)

    ./compiler/pascal26 examples/tk/tkinter_facade.npy /tmp/out

    pascal26:5: error: import: tkinter is the Pascal unit .../lib/pcl/tkinter.pas,
    not a Python module — a bare NilPy import resolves to Python (.py/.npy) only.
    To reach the Pascal unit, name it with its extension: import 'tkinter.pas' as tkinter

## Why the tests must NOT be rewritten here

The other half of the cascade was test fixtures importing Pascal units under
`test/nilpy_units/`, and those were correctly rewritten to the quoted spelling.
These six are the opposite case. `import tkinter as tk` is what every real
tkinter program on earth contains; rewriting the examples to `import
'tkinter.pas' as tk` would make them show a spelling no Python source has, and
would put NilPy's flagship GUI surface out of reach of unmodified CPython code —
against the upward-compatibility rule (if it works on CPython it must work on
NilPy).

## Verified fix

One name added to `PyRtlUnitServesPython`:

```pascal
            (lo = 're') or (lo = 'subprocess') or (lo = 'tempfile') or
            (lo = 'tkinter');
```

Measured 2026-08-19 against a self-host fixedpoint built on `5b1539fc7` with
that one line applied ("converged after 1 round(s)"): all six of
`examples/tk/{callbacks,facade_and_paths,field_class_identity,import_in_body,shadow_format_except,tkinter_facade}.npy`
compile OK, with **no edit to any example or test**. Reverted afterwards — this
checkout does not hold the A/P slot.

## Also worth deciding (not this ticket)

There is no spelling for a from-import of a Pascal unit: `from 'basehook.pas'
import ConfigBase` is refused with *expected a module name after from*. That cost
`test/test_nilpy_subclass_unit_base.npy` one of its three assertions (recorded in
that file's header). Whether the quoted form should be accepted after `from` is a
Track U call, filed as `decide-should-from-accept-a-quoted-foreign-file`.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.

## RESOLVED 2026-08-19 by frank3 (A/P slot holder)

One name added to `PyRtlUnitServesPython` (`compiler/parser.inc`), plus an amendment
to the list's own doc comment.

**Why the comment needed changing too.** It read *"When a new **lib/rtl** unit is
written to serve a Python module…"* — describing the sweep that caused this omission
rather than the question the list answers. `tkinter` is `lib/pcl`'s. Where a unit
lives is not the criterion; what it is FOR is. The comment now says so, so the next
`lib/pcl` or `lib/*` unit written to serve a Python module is not missed the same way.

**Verified** (`gate.sh quick` cannot see `test-core`, so the Makefile recipe lines
were run directly):

- all seven `examples/tk` compile jobs — `tkinter_facade`, `uses_tkinter_and_configparser`,
  `field_class_identity`, `callbacks`, `import_in_body`, `shadow_format_except`,
  `facade_and_paths` (frank2 reported six; there are seven)
- the three Xvfb run-and-diff jobs — output identical to `.expected`
- both `test/` jobs naming tkinter, including
  `test_nilpy_renamed_class_is_not_a_module`, whose point is a *refusal* and which
  therefore had to be checked for the right failure rather than for success
- self-host fixedpoint converged; `gate.sh quick` GREEN

### Still refused, and correctly — NOT part of this bug

`examples/tk/hello.npy` and `examples/tk/widgets.npy` do `import tk`, which is
`lib/pcl/tk.pas` — the thin Tcl/Tk binding that `tkinter.pas` is built ON TOP OF, not
Python's module. **CPython has no `tk` module**, so no unmodified Python source can
name it, and the argument that saved `tkinter` does not apply. These two are the
genuine rewrite case (`import 'tk.pas' as tk`) and were left for the cascade cleanup.

The pair is a good statement of where the line falls: same directory, same feature,
opposite answers — because the question is whether a Python program could have
written that import.
