# String `Copy` / `Trim` not available

- **Type:** feature (library / builtin)
- **Status:** done (2026-06-19)
- **Owner:** Claude B
- **Opened:** 2026-06-19 (discovered by `make demos`: examples/adventure)

## Symptom

`examples/adventure/engine.pas` uses `Copy(s, a, len)` and `Trim(s)`:

```
pascal26:156: error: undefined variable (Copy)
```

`examples/adventure/engine.pas:156,166,176` need `Copy` and `Trim`; neither
exists as a builtin or in `lib/rtl`.

## Direction

Provide `Copy(s, index, count)` (1-based substring) and `Trim(s)`. `Copy` is a
classic Pascal builtin — decide builtin vs RTL unit; `Trim` is RTL. Mind frozen
vs managed string modes. Track B; current platform first. Add unit tests and
fold `examples/adventure` toward green in `make demos`.

- See `examples/adventure/EXPECTED-FAILURES.md` for the app's known gaps.

## Log
- 2026-06-19 — opened from the demos compile-smoke dashboard.
- 2026-06-19 — **done.** `Copy(s, index, count)` (1-based, count clamped to
  end, out-of-range -> '') and `Trim(s)` (strip <= ' ' both ends) added in
  `lib/rtl/strutils.pas`; `Copy` is definable as a plain unit function (not a
  reserved builtin). `test/lib_strutils` asserts both in `make lib-test` (green).
  `examples/adventure/engine.pas` now `uses strutils` and clears the Copy
  blocker. Adventure still FAILs on later compiler gaps (mixed-case builtins —
  bug-builtin-write-case-sensitive; then Text-file I/O per its
  EXPECTED-FAILURES.md F1), not on Copy/Trim.
