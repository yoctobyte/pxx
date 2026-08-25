---
track: D
prio: 30
type: docs
blocked-by: []
summary: "{$NILCHECKS ON|OFF} and --no-nil-check shipped 2026-08-21 and are not in docs/reference/directives.md or modes.md. The row is unusual enough to be worth a sentence: the directive is tri-state, so ON and OFF do different things depending on which site class you are looking at."
status: backlog
---

# Document `{$NILCHECKS}` and `--no-nil-check`

Landed 2026-08-21 by [[feature-a-emitted-nil-checks]] (Track A). Filed for D
because `docs/**` is D's lane; the compiler side is done and green.

## The row

`docs/reference/directives.md`, in the checking-directives table next to `{$R}`
/ `{$Q}` / `{$I}`:

| Directive | Effect | Default | Flag |
| --- | --- | --- | --- |
| `{$NILCHECKS ON\|OFF}` | Nil-pointer checking. | see below | `--no-nil-check` |

## Why it needs a sentence and not just a row

The Default column cannot hold the answer, because there isn't one answer. The
directive is **tri-state** — the compiler distinguishes "on", "off" and *"the
author said nothing"* — and the two site classes resolve the third state in
opposite directions:

- **calls** — a method on a nil instance, a call through a nil procvar or
  method pointer, a method on a nil interface: **checked by default**. The
  check costs ~2% and replaces a fault that lands frames away from the call
  (or, on a target with no signal runtime, does not land at all).
- **bare pointer derefs** — `p^`, `p^.f`, `p^[i]`: **not checked by default**,
  because that is a test inside whatever loop the deref sits in and on the PC
  targets the MMU already reports it at exactly the right instruction. Measured
  +6% on a loop that does nothing else.

So `{$NILCHECKS ON}` *adds* the deref checks, `{$NILCHECKS OFF}` *removes* the
call checks, and each is a no-op for the other class. `--no-nil-check` is the
master off for both.

What a checked site does when it fires: calls `PXXNilRef`, which prints
`Runtime error 216 (nil reference)` and halts — or, with `SysUtils` in the
program, raises a catchable `EAccessViolation`. **That catchability is the
point of the feature**, and is worth saying in the prose: it is what a raw
memory fault can never offer, since `try..except` does not run for one.

`docs/reference/modes.md` wants the `--no-nil-check` line too.

## Gate

D's usual: prose consistent, and any snippet compiles against `$(PXX_STABLE)`.
Note the pin must be v369 or later for the examples to build at all.
