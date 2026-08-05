---
summary: "InterLockedIncrement and family now exist (lib/rtl/palatomic.pas) but need an explicit `uses palatomic`; FPC declares them in the `system` unit, so real code calls them with no uses line at all"
type: bug
track: A
prio: 30
---

# `InterLocked*` should be reachable with no `uses`, like FPC's

- **Type:** bug (compat surface) — Track A, because the always-available unit
  is `compiler/builtin/builtin.pas`, which is A's ground
- **Status:** backlog
- **Opened:** 2026-08-05

`InterLockedIncrement/Decrement/Exchange/ExchangeAdd/CompareExchange` (and the
`*64` peers) were missing from the RTL entirely and now live in
`lib/rtl/palatomic.pas`, verified line-for-line against FPC. FPC declares them
in the `system` unit, so a source that uses them carries no `uses` line for
them — which means FPC code still does not compile as-is.

## Why they are in their own unit and not palsync

`palsync` already uses the same `__pxxatomic_*` intrinsics, and putting them
there was the first attempt. It does not work: `palsync` uses `palthread`,
`palthread` contains `__pxxclone`, and reaching it fails the compile with

```
__pxxclone (thread creation) requires --threadsafe or {$threadsafe on}
```

An atomic counter needs no thread support to *compile* — a refcount in a
single-threaded program is a normal use — so it must not drag that gate in.
`palatomic` therefore has no dependencies at all.

## The ask

Surface the same eleven functions from the auto-included builtin unit
(`compiler/builtin/builtin.pas`, the `system`-unit analogue), so
`InterLockedIncrement(n)` resolves with no `uses`. They are one-line wrappers
over intrinsics the compiler already has, so this should be a declaration
question, not an implementation one.

Check first whether that shadows or conflicts with `palatomic` for code that
does say `uses palatomic` — if it does, `palatomic` becomes the thin
re-export rather than the definition.

## Coverage

`tools/fpc_diff_probe.sh` case `interlocked-family` — eleven assertions across
both widths, currently passing with the `{$IFDEF PXX} uses palatomic; {$ENDIF}`
split. That `{$IFDEF}` is exactly what this ticket removes.

## Gate

Track A: `make test` + self-host fixedpoint (byte-identical).
