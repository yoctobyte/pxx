---
slug: bug-n-an-fstring-conversion-with-a-format-spec-is-refused
title: an f-string conversion with a format spec is refused
summary: >
  `f"{x!r:>8}"` failed to compile with "only the !r and !s f-string
  conversions are supported", although `{x!r}` and `{x:>8}` each compiled.
  The conversion arm required the hole to END after `!r`/`!s`. FIXED
  2026-10-03 (frankuser): a conversion followed by `:` is remembered and the
  format-spec arm wraps the hole as pyformat_of(pyrepr_of(x), ">8"), the
  order CPython applies them in.
track: N
type: bug
prio: 50
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

Found by a leak probe that used `{str(k)!r:>8}` in a loop. Covered now:
`!r` and `!s` with a fill/align/width spec, and with a NESTED width
(`{name!r:>{w}}`), which goes through the same spec arm.

Test: test/test_nilpy_an_fstring_conversion_takes_a_format_spec.npy,
byte-identical to CPython under -dPXX_HEAP_DEBUG and on i386.

`!a` (ascii()) is still refused by name, as before.
