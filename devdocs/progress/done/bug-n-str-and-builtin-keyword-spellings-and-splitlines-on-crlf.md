---
slug: bug-n-str-and-builtin-keyword-spellings-and-splitlines-on-crlf
title: str/builtin keyword spellings are refused, and splitlines() splits only on LF
summary: >
  `s.split(",", maxsplit=1)`, `s.split(sep=",")`, `int("ff", base=16)`,
  `round(x, ndigits=2)`, `s.expandtabs(tabsize=4)` and
  `s.splitlines(keepends=True)` each failed with "undefined variable (<name>)"
  although the positional spellings compiled (`splitlines(True)` was refused
  outright). On a VARIANT receiver the split/splitlines keywords compiled and
  then raised "'str' object has no attribute 'split'" at run time. And
  splitlines() broke only on LF: CRLF text answered ['a\r', 'b'], silently.
  FIXED 2026-10-03 (frankuser).
track: N
type: bug
prio: 55
owner: frankuser
status: done
---

## What changed (2026-10-03, frankuser)

- split/rsplit consume `sep=` and `maxsplit=` in declaration order; a lone
  `maxsplit=` gets the default separator, an explicit None, which the
  existing arity logic maps to the whitespace-with-limit form.
- splitlines joins expandtabs on the zero-or-one-argument row, with
  pystr_splitlines_n(s, keepends); the keywords `keepends=` / `tabsize=` are
  consumed by name.
- int's radix and round's ndigits consume `base=` / `ndigits=` through one
  helper, PyEatKwNamed, which enumerate's `start=` now uses too.
- pystr_splitlines uses CPython's boundary set: CR LF as one, a lone CR, VT,
  FF, \x1c-\x1e, and as UTF-8 sequences NEL, U+2028 and U+2029.
- A variant receiver: TPyBytes declares split/rsplit/splitlines without those
  parameters, so the name went to the class dispatcher and the keyword bound
  against nothing. When every keyword in the call belongs to the str row and
  no class's same-named method declares any of them, the call now takes the
  str-first path (PyStrKwCallOnlyStrTakes). A user class whose own split takes
  `maxsplit=` keeps the dispatcher.

Test: test/test_nilpy_builtin_and_str_method_keywords_bind_by_name.npy,
byte-identical to CPython under -dPXX_HEAP_DEBUG.

## Still divergent, recorded rather than ticketed

Text-mode READS do not translate newlines: CPython's default `newline=None`
turns CR LF and a lone CR into LF on read, and open() here returns the bytes
as they are (`newline=` is accepted and judged, not applied). So `f.read()`,
`readlines()` and `for line in f` keep the '\r' of a CRLF file;
`f.read().splitlines()` and `line.strip()` are correct after this fix,
`line.rstrip("\n")` is not. A design question for I/O (and for ESP), not a
one-site fix. Also seen and not fixed: `zip(strict=)` (3.10, past NilPy's 3.9
claim). The nested .format field seen in the same probe is fixed separately:
bug-n-str-format-refuses-a-nested-field-in-its-spec.
