---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`except (A, B) as e` binds ONE variable typed as the FIRST listed class, so when B is caught its object is read at A's field offsets. Harmless inside the Python tree (every arm descends from PyException) and a SILENT WRONG VALUE the moment a tuple crosses hierarchies — measured: `except (ValueError, su.Exception) as e` prints an EMPTY message once the two classes' layouts differ by one field."
---

# An `except` tuple's binder is typed by its first arm, whatever the others are

`PyParseTry` (`compiler/pyparser.inc`) allocates one binder symbol per handler
and types it from the first class listed:

```pascal
handlerVar := AllocVar(handlerName, tyClass);
Syms[handlerVar].RecName := recId;   { the first listed class }
```

Every arm's handler node then shares that symbol. Inside Python's own hierarchy
that is harmless by construction — all arms descend from `PyException`, so any
member they share sits at a shared offset. It stops being harmless the moment a
tuple lists classes from two hierarchies, which NilPy can express:

```python
import sysutils as su
try:
    x = su.StrToInt("abc")
except (ValueError, su.Exception) as e:
    print(e)
```

`e` is typed `ValueError` (pylib's tree) and holds a sysutils object.

## Measured 2026-08-14

With sysutils' `Exception` given one extra field before `msg` — a change nothing
forbids now that the two roots are independent:

| | result |
| --- | --- |
| today | compiles clean, runs clean, prints an **empty** message |
| after the guard added for the bare-`Exception` bridge | **unchanged** — the guard covers the bridge only |

Not a crash. A plausible wrong value, read from the wrong offset, inside an
exception handler. Exactly the failure class
`devdocs/dev/debugging-playbook.md` opens with.

## Fix: bind at the JOIN of the arms

The static type of `e` should be the most-derived common ancestor of the listed
classes, not the first one. For a single class and for any same-tree tuple that
changes nothing. For a cross-tree tuple the join is `TObject`, so `e.Message`
becomes *"no such member"* — a compile error where there is currently a wrong
string, which is the right trade for a construct this rare.

**The bridge stays a deliberate exception to that rule.** A bare `except
Exception:` unifies `PyException` and sysutils' `Exception` on purpose
(decide-pylib-exception-vs-sysutils-exception option 5) and their join is
`TObject`, so the join rule would break `print(e)` on it. That case is already
guarded by `PyBridgeRootCi`, which refuses to compile when the one member it
depends on (`msg`) stops agreeing. Checked exception, not an unchecked one.

## Gate

`except (ValueError, su.Exception) as e` reporting a missing member rather than
printing an empty string under a diverged layout; every existing `except (A, B)`
row in the NilPy suite unchanged; the bridge tests
(`test_nilpy_rtl_exception_surface`, `test_nilpy_pyexception_bare_vs_qualified`)
green.

## HOLD 2026-08-14 (user) — do not build the join fix yet

The user is reconsidering the approach and will look at this later: *"maybe we
do need another approach after all."* So the "bind at the JOIN of the arms"
section above is a RECOMMENDATION, not a decision — do not start on it.

Priced down to 20 to keep it out of `next`. The bridge case is guarded
(`PyBridgeRootCi` refuses to compile on a diverged layout), so nothing here is a
live silent-wrong-value: reaching it needs a hand-written cross-hierarchy
`except` tuple AND a layout change to sysutils' Exception.

Raise the prio again when the direction is settled.
