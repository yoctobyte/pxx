---
slug: bug-n-str-format-refuses-a-nested-field-in-its-spec
title: str.format() refuses a nested field in its spec, and !r drops its spec
summary: >
  `"{:>{w}}".format("a", w=4)` raised ValueError ("unsupported format spec")
  where CPython pads to the width taken from the argument; the f-string
  spelling already worked. Both the compile-time renumbering of named fields
  (PyFormatRenumber) and the run-time spec scan (PyFormatApply) stopped at the
  first close brace and cut the spec in half. And `"{!r:>8}".format(x)`
  applied the repr and dropped the spec. FIXED 2026-10-03 (frankuser).
track: N
type: bug
prio: 45
owner: frankuser
status: done
---

## What changed (2026-10-03, frankuser)

- Both scans are brace-balanced. At compile time the nested names are
  renumbered with the outer field (PyFormatRenumberName, one helper for both);
  at run time PyFormatExpandSpec substitutes each nested field's text into
  the spec before it is applied. The outer field takes its automatic index
  before the nested ones, as in CPython, so `"{:<{}} {:>{}.{}f}"` reads
  name, width, value, width, precision in that order.
- A `!r` conversion with a spec formats the repr with the spec.

Test: test/test_nilpy_str_format_nests_a_field_in_its_spec.npy (automatic,
numbered and named nested fields, a nested fill, a two-column table),
byte-identical to CPython under -dPXX_HEAP_DEBUG.
