---
summary: "Revert the __pxx_clock workaround in lib/rtl/pxxcio.pas — its blocker (the explicit Int64() cast of a NativeInt on 32-bit) is fixed, and the idiomatic one-liner is verified correct on x86-64, i386 and arm32"
type: task
track: B
prio: 45
owner: claude-B
---

# Revert the `__pxx_clock` Int64-cast workaround

- **Type:** task — Track B (`lib/rtl`)
- **Status:** done
- **Opened:** 2026-08-05
- **Filed by:** Track A, on closing
  `bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit`.

Track A owns the fix but not the file: `lib/rtl/pxxcio.pas` is Track B's lane,
so this is handed over rather than done in place.

## What to do

`devdocs/dev/track-b-workarounds.md` row 1 and the comment block in
`lib/rtl/pxxcio.pas`'s `__pxx_clock` both say "revert to the one-liner when that
closes". It has closed. Replace the two-step implicit widening with the
idiomatic form:

```pascal
Result := Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000;
```

Then delete the WORKAROUND comment block above it and drop the row from
`track-b-workarounds.md`.

## Already verified (so this is mechanical, not exploratory)

The exact expression, on the exact shape (`NativeInt` record fields), gives
`1234567890` for `Sec=1234, Nsec=567890000` on **x86-64, i386 and arm32** with
the fixed compiler — measured. And C's `clock()` compiled through `crtl` now
returns plausible values with a non-negative delta between successive calls on
all three, which is the behaviour the workaround was protecting.

The same shape is covered by `test/test_int64_cast_of_nativeint.pas` (Track A's
regression test), so a reintroduction of the compiler bug would be caught before
this line is.

## Gate

Track B's usual: build with `$(PXX_STABLE)`, `make lib-test`. **Note the pin
boundary** — `PXX_STABLE` is `pinned`, and the compiler fix is not pinned yet.
Until Track A runs `make pin`, `pinned` still has the bug and the reverted
one-liner would be WRONG when built against it. So either wait for the pin, or
verify against `compiler/pascal26` and land the revert only once `pinned` has
moved. That ordering is the only real hazard here.

## Log
- 2026-08-09 — resolved, commit c6b9b078d.
