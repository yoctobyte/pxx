---
summary: "FPC compiles Assert OUT unless -Sa/{$ASSERTIONS ON} and appends '(file, line N)' to the message; pxx always evaluates and omits the position. Adopt both, neither, or one?"
type: decision
track: U
prio: 40
---

# Decide: `{$ASSERTIONS}` and the assertion message format

- **Type:** decision — **Track U**
- **Status:** open
- **Opened:** 2026-08-05
- **Raised by:** Track A, closing
  `compat-pascal-assert-halts-instead-of-raising-eassertionfailed`. The
  catchability half is fixed and verified; these two remainders are parity calls
  that were deliberately left rather than folded in.

## Two divergences, both deliberate remainders

### 1. Assertions are always evaluated

FPC compiles `Assert` **out** unless `-Sa` or `{$ASSERTIONS ON}`. pxx always
evaluates it. That is the LAX direction — we run a check FPC skipped — so it
produces no wrong value, but it means:

- a release build carries assertion cost FPC would have removed;
- an assertion with a SIDE EFFECT (`Assert(Advance(x) > 0)`) runs here and not
  there, which is a behavioural difference, not just a performance one.

### 2. The message omits the source position

    FPC : caught: EAssertionFailed: boom (a.pas, line 6)
    pxx : caught: EAssertionFailed: boom

Text only, no behavioural consequence — but any test comparing assertion output
against FPC diverges on every line.

## Why they are one ticket

Implementing `{$ASSERTIONS}` means touching the `Assert` lowering, and that is
the same place the file/line suffix would have to come from (the call site's
position is known there and nowhere later). Doing them separately means opening
that lowering twice.

## Options

1. **Both** — full FPC parity: `{$ASSERTIONS}` / `-Sa` gating plus the
   `(file, line N)` suffix. Most compatible; costs a new directive and a
   position argument threaded into `__pxxAssert`.
2. **Message only** — cheap, removes the visible text divergence, leaves the
   always-evaluated semantics (and its side-effect difference) in place.
3. **Neither** — declare always-on assertions a deliberate dialect choice and
   write it down in `docs/language/**`. Defensible: an assertion that always
   runs is arguably the safer default, and pxx has chosen its own dialect
   before.

## Recommendation

**1**, but low urgency — nothing is silently wrong today. If only one is wanted,
prefer the `{$ASSERTIONS}` gating over the message: the side-effect difference
is behavioural, the message is cosmetic.

Note the ordering: `__pxxAssert` lives in `compiler/builtin/`, so this lands
under Track A's gate. Today's hook change there did NOT need a repin
(`selfhost_fixedpoint.sh` converged) — worth measuring rather than assuming for
the next one.
