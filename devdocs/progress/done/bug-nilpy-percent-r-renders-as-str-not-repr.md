---
track: N
prio: 60
type: bug
---

# `%r` rendered as `%s` — silently, and only for strings

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle (`tools/pydiff.py run`), not by a failing test.

## Measured

```python
print("%r" % "v")        # CPython 'v'      pxx v      WRONG
print("%s" % "v")        # CPython v        pxx v      ok
print("%r" % 5)          # CPython 5        pxx 5      ok
print("%r" % [1, 2])     # CPython [1, 2]   pxx [1, 2] ok
print("%s=%r" % ("k","v")) # CPython k='v'  pxx k=v    WRONG
```

`%r` is `repr()`, not `str()`. The %-format conversion switch lumped the two
together in one arm:

```pascal
's', 'r':
  outS := outS + PyFmtPad(pyvar_print_of(cur), width, False, leftAlign);
```

**Only string operands diverge**, which is exactly what hid it: `repr` and `str`
agree for numbers and booleans, and pxx's containers already render repr-style,
so every non-string probe looked correct.

## Fix

Split the arm. `pyvar_repr` already quotes a string and delegates list/dict/bytes
to their own repr, so this is one call, not new logic.

## Second bug in the same pass: repr's QUOTE SELECTION

`repr("it's")` gave `'it\'s'` where CPython gives `"it's"`. Python prefers `'`,
switches to `"` when the string contains a single quote and NO double quote, and
keeps `'` (escaping it) when it contains both. `PyReprQuote` always used `'`.

Fixed with a Boolean and two explicit branches — deliberately NOT a
`delim: Char` variable. The first attempt used one, and it silently emitted
EMPTY delimiters: a Char VARIABLE does not convert to a string the way a Char
CONST does, because the conversion is keyed on the expression SHAPE rather than
its type (`project_string_conversion_shape_blindspot_pattern`). That landmine is
live and cost a build cycle here.

## Verified

`test/test_nilpy_percent_repr.npy`, wired into `make test-nilpy`,
byte-identical to CPython. Confirmed RED pre-fix (`v` where `'v'` is required).
Covers `%r` of str / int / float / list / dict / bool, `%r` with width and
left-align padding, `%s` alongside it, the other conversions (`%d %05.2f %x`),
and all three quote-selection cases (single only, double only, both).

## Also noted by the same sweep, NOT fixed here

- `pow(2, 10)` — undefined variable (loud).
- `"{:,}".format(n)` — thousands separator unsupported; raises at run time and
  ABORTS rather than being catchable.
- `"abcdef"[1:5:2]` — stepped slices other than `[::-1]` refused at compile
  time (explicit diagnostic).

All three are loud rather than silent, so none is in this bug's family. Filed
as [[bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice]].
