---
track: N
prio: 20
type: feature
blocked-by: []
status: done
found-by: frankuser (2026-09-29)
tags: [nilpy, stdlib, random]
summary: "random.sample(population, k) exists, both as `random.sample` and through `from random import sample`. It returns k distinct elements as a new list and leaves the population untouched. A list, str, range or tuple population works. k out of range raises ValueError, and a set or dict raises TypeError, as in CPython 3.11+. The values differ from CPython's (the generator is not the Mersenne Twister); the result's shape matches."
owner: ""
---

# random.sample

## Implementation

- `pyrandom_sample` (compiler/builtin/pylib.pas) is a partial Fisher-Yates
  over pylist_v's copy of the population. Both the copy and the result are
  accounted for.
- It has one row in PyStdlibCallProc (`'random.sample'`). The from-import
  arm binds through the same table (PyStdAliasRecord), so the one row
  covers both spellings.

## Rows

- test/test_nilpy_random_sample.npy, with .expected from CPython. It
  compares shape only (type, length, distinctness, membership, the
  population unchanged, both errors), plus the set of values a 1-sample
  draws over 200 tries. Rows: x64 (rsample26), i386 and wasm32.
- test/test_nilpy_random_sample_releases_its_copy.npy under
  PXX_ALLOC_CENSUS: `drop` stays at 29 live over 5000 samples; `keep` is
  the positive control and trips the bound.
- wasm32: the same value row, and the census row without the control.
  Both depend on bug-a-a-variant-store-of-an-object-does-not-retain-on-wasm32.
