# `IntToStr` not available

- **Type:** feature (library)
- **Status:** done (2026-06-19)
- **Owner:** Claude B
- **Opened:** 2026-06-19 (discovered by `make demos`: examples/primes/sieve.pas)

## Symptom

`examples/primes/sieve.pas:92` calls `IntToStr(n)`:

```
pascal26:92: error: undefined variable (IntToStr)
```

No `IntToStr` exists in `lib/rtl` or the builtins.

## Direction

Add `IntToStr` (SysUtils-style) to the RTL — likely `lib/rtl` next to the
existing string helpers. Integer (and ideally Int64) → decimal string. Track B
work; current platform first, cross parity later. Add a small unit test and seed
`examples/primes` into `make demos` going green.

## Log
- 2026-06-19 — opened from the demos compile-smoke dashboard.
- 2026-06-19 — **done.** `IntToStr(Integer)` added in `lib/rtl/strutils.pas`
  (housed there, not `sysutils`, which is hard-skipped — see
  bug-sysutils-unit-hard-skipped). `examples/primes/sieve.pas` now compiles +
  runs correct against pinned v9 (π(10^6)=78498, largest 999983); demos shows OK.
  `test/lib_strutils` asserts output in `make lib-test` (green). Int64 overload
  deferred until a demo needs it.
- 2026-06-20 — commit reference (board checker): landed in 8e43982
