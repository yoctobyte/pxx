---
prio: 42
---

# bignum operator layer: TBigInt + - * div mod comparisons — Track B

- **Type:** feature (library) — Track B
- **Status:** working
  [[feature-lib-vecmath]] / [[feature-pascal-complex-numbers-ucomplex]]
- **Owner:** fable-p

## What

`lib/rtl/bignum.pas` already has the machinery as functions (BigAdd,
BigAddSigned, BigSub, BigMul, ... TBigInt record). Add the operator layer
on top: `+ - *` and `div` (tkDiv IS in the declarable set), `= <> < <= >
>=` via the existing signed compare. `mod` needs the op-set one-liner —
note on [[feature-pascal-operator-slash-overload]]. Keep the function API
untouched (operators = thin wrappers).

## Why

Makes bignum pleasant (`c := a * b + a;` on 200-digit ints) and is the
third operator-overloading workout: unlike complex/vecmath these records
hold heap/managed payloads (check TBigInt's rep!) — operator results as
temporaries in chained expressions exercise the managed-record temp
lifetime path (see project_managed_record_byval_arg_temp landmine). If
TBigInt is a managed record, this test coverage is exactly where a
refcount/double-free bug would surface.

## Tests

lib-suite golden test: factorial(50), 2^512, +/- around sign flips,
div/mod identities (a = (a div b)*b + a mod b), comparison matrix, chained
expressions forcing operator temporaries. All integer-exact — no FP
determinism concerns.

## Gate

Track B: build with `$(PXX_STABLE)`, `make lib-test` green. A managed-temp
crash found here → Track A ticket with minimal repro, don't work around.
