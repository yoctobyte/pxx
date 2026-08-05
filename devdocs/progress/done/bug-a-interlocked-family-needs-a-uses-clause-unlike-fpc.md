---
summary: "InterLockedIncrement and family now exist (lib/rtl/palatomic.pas) but need an explicit `uses palatomic`; FPC declares them in the `system` unit, so real code calls them with no uses line at all"
type: bug
track: A
prio: 30
owner: claude-A
---

# `InterLocked*` should be reachable with no `uses`, like FPC's

- **Type:** bug (compat surface) — Track A, because the always-available unit
  is `compiler/builtin/builtin.pas`, which is A's ground
- **Status:** done
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

## Resolution (2026-08-05)

The eleven functions are now declared in `compiler/builtin/builtin.pas` — the
`system`-unit analogue — as one-line wrappers over the same `__pxxatomic_*`
intrinsics, with a token scan pulling that unit when an `InterLocked*` call
appears. That is the mechanism `Abs`/`Sqr`/`Delete`/`Insert` already use, not a
new one.

Both of `palatomic`'s guards are carried over deliberately, for the reasons it
records: `{$IFDEF CPU64}` on the `*64` peers (a 32-bit target has no
single-instruction 64-bit read-modify-write and the DECLARATIONS alone would
break those builds) and `{$ifndef PXX_ESP}` (no atomic intrinsics there).

### The ticket's "check first" — checked

*"Check whether that shadows or conflicts with `palatomic` for code that does
say `uses palatomic`."* It does not:

- `uses palatomic` still compiles and produces identical output — a user RTL
  unit shadows a builtin of the same name, which is the documented rule and the
  same one that lets a program override any builtin;
- the duplicate-definition warning added earlier today reports **0** on that
  program, which is independent confirmation that the two live in different
  units rather than colliding.

So `palatomic` did NOT need to become a thin re-export; both spellings stand.

### Verified

Byte-identical to FPC with **no `uses` line**, across all eleven functions. The
test pins the return-value contract explicitly, since that is the part most
likely to be silently wrong: Increment/Decrement return the value AFTER,
Exchange/ExchangeAdd/CompareExchange the value BEFORE. It also pins
`CompareExchange`'s swap AND no-swap cases, because the intrinsic takes
`(expected, new)` while FPC takes `(new, expected)` — an argument swap that
would produce plausible wrong results rather than an error.

`testmgr --tier native` **1166/1166 pass**. Locked in as
`test/test_interlocked_no_uses.pas`.

The `{$IFDEF PXX} uses palatomic; {$ENDIF}` split in
`tools/fpc_diff_probe.sh`'s `interlocked-family` case can now be removed;
that file is Track T's lane, so it is left for them.

## Log
- 2026-08-05 — resolved, commit fc75ba020.
