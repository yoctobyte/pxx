---
slug: feature-n-itertools-is-a-plain-python-shim
title: itertools is a plain-Python shim
summary: >
  `import itertools` was consumed with no backing unit: every name in it was
  `undefined variable` except `count`, which the frontend special-cased onto
  pylib's TPyCounter. DONE 2026-10-03 (frankuser): lib/rtl/mimic_itertools.py
  implements the module as generators, mirroring CPython's documented
  "roughly equivalent" code, and is picked up by the shim resolver.
track: N
type: feature
prio: 40
owner: frankuser
status: done
---

## What is there

count, cycle, repeat, accumulate (func=, initial=), chain, from_iterable,
compress, dropwhile, takewhile, filterfalse, groupby (key=), islice (1-3
bounds), starmap, tee, zip_longest (fillvalue=), pairwise, product (repeat=),
permutations, combinations, combinations_with_replacement. `batched` (3.12)
is absent.

Divergences, in the shim's docstring: groupby yields each group as a LIST;
tee materialises its input; `chain.from_iterable` is spelled
`from_iterable` at module level; starmap spreads at most four arguments.

## What it took

Writing the shim surfaced five compiler bugs, all fixed the same day, each
with its own done ticket:

- bug-n-a-for-over-a-variant-drains-a-generator-before-the-first-iteration
- bug-n-a-module-qualified-generator-call-is-called-not-built
- bug-n-a-def-returning-a-generator-call-is-typed-bool
- bug-n-a-generator-does-not-hold-a-reference-to-its-object-arguments
- bug-n-next-on-an-untyped-value-binds-the-old-counter-overload

## Verified

test/test_nilpy_mimic_itertools.npy: every function, both import spellings,
output byte-identical to CPython 3, under -dPXX_HEAP_DEBUG and on i386.
