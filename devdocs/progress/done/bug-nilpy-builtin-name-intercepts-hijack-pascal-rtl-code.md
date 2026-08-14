---
track: A
prio: 60
type: bug
blocked-by: []
summary: "16 Python-builtin name intercepts in the SHARED parser are gated on `isNilPy`, which is true for the whole compilation including every PASCAL unit loaded into it. Measured biting instance: sysutils' own `Format(fmt, args)` inside Exception.CreateFmt lowered to pyformat_v in any .npy that reached sysutils, so an RTL raise came back as `unsupported format spec \"\"` instead of its message. Fixed for `format`; the other 15 are unaudited."
status: done
owner: agent-A
---

# NilPy builtin-name intercepts fire inside Pascal RTL units

`NilPyUserCode` exists precisely for this (`compiler/symtab.inc:4`) and its own
comment says why: *"isNilPy is true for the WHOLE compilation, including every
PASCAL unit loaded into it (pylib and friends), so this Python-only fallback was
hijacking ordinary Pascal member resolution inside those units."* The member
path was fixed; the **name-keyed call intercepts were not**.

## The measured instance (fixed 2026-08-14)

`else if isNilPy and CaseEqual(name, 'format')` (`compiler/parser.inc`) claimed
sysutils' `Format(fmt, args)` — a call the Pascal RTL genuinely makes, inside
`Exception.CreateFmt` — and lowered it to Python's `format(v, spec)`
(`pyformat_v`). Any `.npy` reaching sysutils got `unsupported format spec ""`
where the RTL's message should have been.

It stayed invisible for as long as it did because pylib's `Exception` was merged
with sysutils' by name, so sysutils' `CreateFmt` body was not the one that ran.
Renaming pylib's root to `PyException` (option 5 of
[[decide-pylib-exception-vs-sysutils-exception]]) uncovered it immediately.

Fixed by switching that one arm to `NilPyUserCode`.

## What is unaudited

Same shape, same file, all still on `isNilPy`:

`__name__` `__file__` `pystr_of` `len` `int` `exec` `input` `open` `float`
`map` `filter` `next` `bool` `str` `round` `divmod`

Two things kept most of them quiet and neither is a guarantee:

- **case.** `(name = 'str')` is exact, so Pascal's `Str` misses it; `len`,
  `format`, `round`, `divmod` use `CaseEqual` and would match a Pascal
  spelling. `format` is the one where a Pascal RTL routine of that name
  actually exists — today.
- **an extra token test.** `round` only fires on a two-argument call, which is
  what keeps Pascal's one-argument `Round` working. That is a guard bought by
  accident, not by design.

Both protections evaporate the moment a library grows a routine named `Len`,
`Open`, `Next` or `Filter` — and the failure is a plausible wrong VALUE inside
an RTL unit, far from anything the user wrote.

## Fix

Audit all 16 against `NilPyUserCode`. Expect most to be a one-word change; the
interesting ones are any that deliberately want to fire inside pylib itself —
if there are none, the predicate can simply be swapped everywhere and the arm
list stops being a thing to remember.

## Gate

`make test-nilpy` + the NilPy canaries in `--tier quick` + self-host
byte-identical. `test_nilpy_rtl_exception_surface.npy` is the regression the
`format` arm produced.

## RESOLVED 2026-08-14 — all 17 swapped, none wanted the wider predicate

Audited every name-keyed intercept in `compiler/parser.inc` and switched each
from `isNilPy` to `NilPyUserCode`. The ticket's own guess was right: **not one
of them has a reason to fire while a Pascal unit is being compiled**, so the arm
list stops being a thing to remember — the predicate is now uniform and the
question "does this one need the narrow form?" has one answer.

`__name__` `__file__` `pystr_of` `len` `hex`/`bin`/`oct` `int` `exec` `input`
`open` `float` `map` `filter` `next` `bool` `str` `round` `divmod`

The one that was doing real damage beyond `format` (fixed earlier, commit
6ed45773f) is **`pystr_of`**: the NilPy lexer desugars an f-string hole `{x}` to
`pystr_of(x)`, and the arm rewrites the call when the argument is a `tyClass`.
pylib is Pascal and calls `pystr_of` directly all over its own renderer, so
those calls were being rewritten too. They now take the ordinary Pascal overload
path, which is what a Pascal call should do.

### Verified

- The 18 builtins above, exercised in one `.npy` and diffed against CPython —
  identical output including `hex/bin/oct`, `round(2.567, 2)`, `divmod(7, 2)`,
  `map`/`filter`/`next`, and an f-string with a `:g` spec.
- **An imported `.py` module still gets them**: `NilPyUserCode` is
  `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`, and `ParsePyUnit` turns
  `PyExprMode` on for a module body. A module calling `len`/`str`/`hex` matches
  CPython — that half is what the predicate exists to keep, and it is the half
  a naive `CurrentUnitIdx < 0` would have broken
  (bug-nilpy-object-reclamation-disabled-inside-py-modules, same trap).
- `test_nilpy_rtl_exception_surface` and
  `test_nilpy_pyexception_bare_vs_qualified` unchanged; self-host converges at
  generation 1; `gate.sh quick` green.

### Not covered, deliberately

The non-name-keyed `isNilPy` uses — trailing-comma tolerance, keyword-argument
binding, star-args, the member-access arms — were left alone. They key on
GRAMMAR, not on an identifier a Pascal library might also declare, so they
cannot be claimed by a name collision, which is what this ticket is about.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
