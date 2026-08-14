---
track: N
prio: 60
type: bug
blocked-by: [decide-merge-variant-c-with-bare-name-collision]
summary: "`repr(Exception('x'))` prints `PyException('x')` and `type(e).__name__` is `PyException`, where CPython says `Exception`. Introduced 2026-08-14 by the option-5 rename: ClassName reports the DECLARED class name and the declared name is now PyException. Ordinary Python branches on type(e).__name__, so this is an upward-compatibility break, not a cosmetic one."
status: done
owner: agent-an
---

# `repr()` and `type(e).__name__` leak the internal `PyException` name

Measured at HEAD:

| | pxx | CPython |
| --- | --- | --- |
| `repr(Exception('x'))` | `PyException('x')` | `Exception('x')` |
| `type(e).__name__` | `PyException` | `Exception` |
| `repr(ValueError('v'))` | `ValueError('v')` | agrees |

Only the ROOT is affected — every named subclass declares its own Python
spelling, so `ValueError`, `KeyError` and the rest are correct. That is exactly
why the existing tests missed it: `test_nilpy_exception_args` asserts
`ValueError('v')` and `KeyError('inner')`, and nothing asserted a bare
`Exception`.

## Cause, and it is self-inflicted

[[decide-pylib-exception-vs-sysutils-exception]] option 5 renamed pylib's root
class to `PyException` so it would stop colliding with sysutils'. `ClassName`
(and therefore `repr` and `type(e).__name__`) reports the **declared** name of
the class, and the declared name is now the internal one. The lexer maps the
bare identifier on the way IN; nothing maps it back on the way OUT.

## Why it matters

`if type(e).__name__ == "Exception":` and error text that embeds `repr(e)` are
ordinary Python. Under NilPy's rule — *if code works on CPython, it must work on
NilPy* — this is a real break, not a divergence to document.

## Fix

**Fixed by construction** by [[feature-a-one-exception-class-in-a-shared-unit]]:
the shared class is NAMED `Exception` and pylib reaches it through an alias, so
`ClassName` is `Exception` again. Verified in the prototype for that ticket
(`bare root ClassName: Exception`).

If that lands, close this with it. The standalone alternative — special-casing
the name in the renderer and in `__name__` — is a second place that has to know
the mapping, and mapping-in-one-direction-only is what caused this.

## Gate

`repr(Exception('x'))`, `str(Exception('x'))`, `type(e).__name__`, and a
subclass's `__name__`, all diffed against CPython. Add the bare-root rows to
`test_nilpy_exception_args.npy` — their absence is why this shipped.

---

## 2026-08-14 — ALREADY FIXED on a branch. Do not start this from scratch.

`feature-a-one-exception-class-in-a-shared-unit` (variant C) fixes this **by
construction** rather than by another rename: pylib's root is named `Exception`
again, as a sibling of sysutils' class of the same name under a shared
`ExceptionBase`, so `ClassName` reports `Exception` because that IS the declared
name. Measured green on `wip/exception-sibling-design` for `ValueError`,
`KeyError`, a user `class MyErr(Exception)`, and `ValueError(42).args[0] + 1`.

That branch also DELETES the pylexer `Exception` -> `PyException` mapping, whose
"maps in, never maps out" asymmetry is what produced this bug in the first
place — so the fix removes the mechanism rather than adding a second rename to
compensate for the first.

**Blocked on [[decide-merge-variant-c-with-bare-name-collision]]**, not on
effort. Picking this ticket up independently would either duplicate that work or
add the compensating rename the branch exists to delete.

---

## Fixed 2026-08-14 by merging variant C — exactly as this ticket prescribed

Landed with [[feature-a-one-exception-class-in-a-shared-unit]] (squashed from
`wip/exception-sibling-design`), per the user's option-A decision on
[[decide-merge-variant-c-with-bare-name-collision]]. **Fixed by construction, not
by a second rename**: pylib's root is named `Exception` again, so `ClassName` —
and therefore `repr()` and `type(e).__name__` — reports the right name because
that IS the declared name.

The pylexer `Exception` -> `PyException` mapping is **deleted**. Its
"maps in on the way, never maps out" asymmetry is what produced this bug, so the
fix removes the mechanism rather than adding a compensating one. That was this
ticket's own argument against the standalone alternative, and it held.

### Measured against the CPython oracle — identical on every row

```
repr(Exception('x'))   Exception('x')        (was PyException('x'))
str(Exception('x'))    x
type(e).__name__       Exception             (was PyException)
repr(ValueError('v'))  ValueError('v')       unchanged
class MyErr(Exception) MyErr                 unchanged
except Exception as e  Exception             binds and names correctly
ValueError(42).args[0] + 1  ->  43
```

### The Gate's test rows — added, and controlled

`test_nilpy_exception_args.npy` now carries the bare root: `repr`, `str`,
`__name__`, `args`, a bare raise/catch, and a subclass's `__name__` (which must
still be the subclass). Expectations regenerated from CPython.

**Their absence really was why this shipped**, and that is now demonstrated
rather than asserted: run against the PINNED pre-merge compiler, the file
differs on **exactly the two new lines** —

```
-bare root Exception('x') x Exception ('x',)
-bare cat  Exception Exception('raised') ('raised',)
+bare root PyException('x') x PyException ('x',)
+bare cat  PyException PyException('raised') ('raised',)
```

— and nowhere else, because every pre-existing row uses a named subclass that
declares its own Python spelling.

## Two things the branch missed, found by grepping for the old name

Reading the branch's diff would not have surfaced either; both were caught by
searching for `PyException` across everything buildable.

1. **`lib/pcl/tkinter.pas` declared `TclError = class(PyException)`** and no
   longer compiled. `gate.sh quick` **cannot see this** — it is a `lib/pcl`
   unit built with `$(PXX_STABLE)` — so after the pin every Track B build would
   have hit it. The pinned compiler was the control: it builds tkinter, HEAD did
   not. Now `class(Exception)`, unambiguous because that unit's `uses` names
   pylib and not sysutils.
2. **The Makefile's expectations for the two uses-order tests were stale.** The
   branch rewrote those tests to assert the QUALIFIED property; the recipes
   still asserted the old bare-name output, in *both* copies of the recipe.

`test_nilpy_pyexception_bare_vs_qualified.npy` passes **unchanged** — its
assertions were always about the observable contract, and only its prose
described the deleted mechanism. That prose is updated; the assertions are not,
which is what makes it the regression test for swapping the mechanism
underneath.

Whole exception family re-checked against CPython:
`empty_exception_subclass`, `except_as_binder_scope`, `exception_args`,
`exception_fstring_message`, `exception_multi_arg`, `exception_no_leak` — all
match. `rtl_exception_surface` matches its recorded expectation (it imports
sysutils, so CPython cannot be its oracle).

## Gate

`gate.sh quick` GREEN + self-host fixedpoint; `make lib-test` GREEN against the
new pin (~80 suites, including the tk-nilpy one that exercises tkinter);
sysutils' own `Exception` surface and named descendants (`EConvertError`)
re-checked.

Re-pinned to **v301** as part of the landing, which was required rather than
tidy: `sysutils` now `uses exceptions`, and the old pinned compiler resolved
that unit only when cwd happened to be the repo root — from anywhere else it
failed with `unit source not found: exceptions`. Verified cwd-independent on the
new pin, and in a fresh `git clone`.

One trap for the next person who adds a builtin unit: `make pin` prints
`git add -u stable_linux_amd64/ … all stable files are tracked, so nothing can
dangle`. That holds only while the frozen builtin SET is unchanged — `-u` does
not stage a NEW file, so the first pin after adding a builtin unit ships a
stable tree missing a source. Caught here by listing the frozen directory
against `git status`; fixed in a follow-up commit.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
