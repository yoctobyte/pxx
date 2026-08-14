---
track: A
prio: 60
type: bug
blocked-by: []
summary: "16 Python-builtin name intercepts in the SHARED parser are gated on `isNilPy`, which is true for the whole compilation including every PASCAL unit loaded into it. Measured biting instance: sysutils' own `Format(fmt, args)` inside Exception.CreateFmt lowered to pyformat_v in any .npy that reached sysutils, so an RTL raise came back as `unsupported format spec \"\"` instead of its message. Fixed for `format`; the other 15 are unaudited."
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
