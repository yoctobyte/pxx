# `IntToStr` not available

- **Type:** feature (library)
- **Status:** backlog
- **Owner:** —
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
