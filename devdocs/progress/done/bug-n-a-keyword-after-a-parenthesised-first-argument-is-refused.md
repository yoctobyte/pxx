---
slug: bug-n-a-keyword-after-a-parenthesised-first-argument-is-refused
title: a keyword after a parenthesised first argument is refused
summary: >
  `max((w for w in words), key=len)` failed with "max has no parameter named
  'key' in the overload taking 2 argument(s)", and so did `max((xs),
  key=len)` -- any call whose first argument opens with '('. PyKwNamesTokPos
  preferred the NEXT token's '(' over the current one, so when the call's own
  '(' was already current it answered the argument's paren; the keyword scan
  then covered the argument only, never saw `key=`, and the call stayed on the
  first-declared overload. FIXED 2026-10-03 (frankuser): the current token is
  asked first -- a current '(' cannot be a callee name.
track: N
type: bug
prio: 50
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

Found by a leak probe of generator expressions consumed by builtins. The
bracketed and bare spellings (`max([..], key=len)`, `max(x for x in xs)`)
compiled; only the parenthesised one was refused. Every call site that asks
PyKwNamesTokPos is covered by the one fix, the method promotions included;
their answer changes only in the inner-paren case, which was the wrong one.

Test: test/test_nilpy_a_keyword_after_a_parenthesised_first_argument_binds.npy
(max/min/sorted over a parenthesised generator with key=, key=lambda and
default=, a parenthesised name, a tuple of tuples), byte-identical to CPython
under -dPXX_HEAP_DEBUG.
