---
slug: bug-n-unpacking-a-str-and-the-unpack-count
title: a str does not unpack, and an unpack does not check its count
summary: >
  `a, b = "xy"` and `first, *rest = word` were refused ("not a list, tuple or
  variant"). An unstarred unpack never checked its count: `a, b = [1, 2, 3]`
  silently dropped the 3, and `a, b = [1]` raised IndexError where CPython
  raises ValueError. FIXED 2026-10-03 (frankuser).
track: N
type: bug
prio: 60
owner: frankuser
status: done
---

## What changed (2026-10-03, frankuser)

- A statically-str source is exploded through pystr_charlist (one element per
  character, multi-byte ones included) before the unpack indexes it.
- An unstarred unpack calls pyunpack_exact(len, n): ValueError "too many
  values to unpack (expected n, got m)" for a sized source, "(expected n)"
  for a str (CPython's wording for an unsized iterable), and "not enough
  values to unpack (expected n, got m)".
- Seen in the same probe and fixed beside it: `range(5)[2]` on a range
  VALUE ("this value cannot be subscripted"), and a comprehension filter of
  several `if` clauses (`[x for x in xs if a if b]`, "a conditional
  expression needs an else"). PyParseCompFilter parses the run and ANDs it;
  the ternary arm leaves an `if` alone only inside a filter and only when no
  `else` follows at its depth.

Tests: test/test_nilpy_a_str_unpacks_and_an_unpack_checks_its_count.npy and
test/test_nilpy_a_range_value_indexes_and_a_filter_takes_two_clauses.npy,
byte-identical to CPython under -dPXX_HEAP_DEBUG.

Not fixed, recorded: `enum` has no module and `collections.namedtuple` is
undefined (both need runtime class creation); a class defined inside a def
does not parse.

Left alone deliberately: the FOR-header unpack (`for a, b in rows`) still
does not check the count -- three values into two names drop the third, one
value raises IndexError. That check would run once per iteration on the
hottest path there is, and it changes only programs that are already wrong;
the assignment unpack is checked because it is not a loop body by itself.
