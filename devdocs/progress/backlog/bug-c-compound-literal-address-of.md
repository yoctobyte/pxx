---
track: C
prio: 30
type: bug
---

# cfront: `*(double*)&(unsigned long long){0x...}` segfaults at runtime

- **Track:** C (cfront). Found 2026-07-19 while probing subnormal math
  (feature-crtl-libm-correctly-rounded-transcendentals).

Taking the ADDRESS of a scalar compound literal and reading through a
pointer cast crashes the compiled program:

```c
double s54 = *(double*)&(unsigned long long){0x4350000000000000ull};  /* SIGSEGV */
```

The scalar-compound-literal path (b368) yields the converted VALUE (shared
cast-conversion path), not an addressable temp — so `&` on it produces a
bogus address instead of materialising storage like the record/array
compound-literal paths do (C99 6.5.2.5: a compound literal IS an lvalue with
storage). gcc compiles-and-runs this fine.

Repro above; expected: prints/uses 2^54. Fix shape: route scalar compound
literals through an anonymous temp (AllocVar + AN_COMPOUND_LITERAL, like the
b381 float-narrow temp) at least when their address is taken.
