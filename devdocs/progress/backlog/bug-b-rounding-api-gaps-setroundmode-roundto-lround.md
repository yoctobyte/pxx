---
track: B
prio: 35
type: bug
blocked-by: feature-a-expose-rounding-mode-intrinsic-to-pascal
summary: "Per-language rounding DEFAULTS are all correct (Pascal banker's = FPC, C round() half-away = gcc, Python round() = CPython incl. round(2.675,2)=2.67) — but the escape hatches are missing: no SetRoundMode/RoundTo/SimpleRoundTo in lib/rtl/math.pas, no lround/llround in crtl"
---

# Rounding: the defaults are right, the APIs around them are missing

- **Type:** bug (Track B — `lib/rtl/math.pas`, `lib/crtl`)
- **Filed:** 2026-08-09 by Track D, at the user's request, after verifying every
  frontend's rounding against its own reference implementation.
- **Owner:** —
- **Related:** [[bug-b-fpc-numeric-compat-floor-ceil-return-float-currency-is-double]]

## First: the defaults are CORRECT. Do not "harmonise" them.

Three frontends, three *different* rounding rules, each one right for its own
language. All measured on 2026-08-09 against the real reference on the same
machine:

| input | 0.5 | 1.5 | 2.5 | 3.5 | -2.5 | |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal `Round` (pxx) | 0 | 2 | 2 | 4 | -2 | ties-to-even |
| **fpc `Round`** | 0 | 2 | 2 | 4 | -2 | **identical** |
| C `round()` (pxx) | 1 | 2 | 3 | 4 | -3 | half-away-from-zero |
| **gcc `round()`** | 1 | 2 | 3 | 4 | -3 | **identical** |
| Nil Python `round()` | 0 | 2 | 2 | 4 | -2 | ties-to-even |
| **CPython `round()`** | 0 | 2 | 2 | 4 | -2 | **identical** |

Nil Python also matches CPython on the float-repr traps that catch most
implementations: `round(2.675, 2)` → `2.67`, `round(1.005, 2)` → `1.0`,
`round(0.125, 2)` → `0.12`, all byte-identical to CPython's output.

**This is worth stating loudly because the three defaults disagree with each
other, and that looks like a bug if you find it from one side.** It is not. C's
`round()` is specified as half-away-from-zero; Pascal's `Round` is a float→int
conversion in the current hardware rounding mode, which defaults to
nearest-even; CPython's `round()` is nearest-even on the exact decimal value.
Making them agree would break all three.

Also verified, since it explains *why* Pascal behaves this way: FPC's `Round`
follows the hardware mode. With real fpc, `SetRoundMode(rmDown)` turns
`0 2 2 4` into `0 1 2 3`, `rmUp` into `1 2 3 4`. `Round` is not an algorithm, it
is a mode-dependent conversion. (Testing this needs runtime values — literal
arguments get constant-folded and appear mode-insensitive.)

## The actual gaps

### Pascal: no way to select a mode, and no `RoundTo` family

`lib/rtl/math.pas` has none of:

- `SetRoundMode` / `GetRoundMode` (+ the `TFPURoundingMode` / `rmNearest`,
  `rmDown`, `rmUp`, `rmTruncate` enum) — FPC's supported way to change the
  mode, and demonstrably effective there.
- `RoundTo(value, digits)` — round to a power of ten.
- `SimpleRoundTo(value, digits)` — the half-away-from-zero variant, which is
  precisely what someone reaches for the first time nearest-even surprises
  them.

So we match FPC's default but not FPC's controls, and the user hitting the
surprise has no supported exit. Note `SetRoundMode` has real teeth on our side
too: `Round` lowers to a mode-sensitive conversion (`vcvtr.s32.f64` on arm32
with FPSCR RN), so honouring the mode is a matter of writing the control word,
not of reimplementing rounding.

### C: `lround` / `llround` are undeclared

Probed the whole family in `lib/crtl`:

| present | missing |
| --- | --- |
| `floor` `ceil` `trunc` `round` `nearbyint` `rint` `lrint` `fmod` `remainder` | **`lround`** **`llround`** |

`lrint` exists but `lround` does not, which is an odd pair to split — they are
the same shape, differing only in rounding rule. `round()` returning a double
that the caller must cast is exactly the friction `lround` exists to remove,
and it is common in real C.

## Acceptance

`SetRoundMode`/`GetRoundMode` present and actually affecting `Round`;
`RoundTo`/`SimpleRoundTo` present and matching FPC; `lround`/`llround`
declared and correct in crtl. The default behaviour of all three frontends is
**unchanged** — a regression test pinning the table above is the useful part of
this ticket, so the next person to find the disagreement cannot "fix" it.

## Log
- 2026-08-09 — filed. Defaults verified correct against fpc, gcc and CPython;
  only the surrounding APIs are missing.

## 2026-08-09 (Track B): three of four done; SetRoundMode is not ours to fake

**Done and gated:**

- `RoundTo` / `SimpleRoundTo` (+ `TRoundToRange`, Single overloads) in
  `lib/rtl/math.pas`, byte-identical to FPC on all 20 measured rows.
- `lround` / `llround` in `lib/crtl`, identical to gcc.
- **The regression test this ticket calls "the useful part":**
  `test/lib_rounding_contract.pas` pins the Pascal side and the RoundTo family,
  `test/cmath_lround.c` pins the C side, and both headers say plainly that the
  three frontends disagree BY DESIGN so the next person cannot "harmonise" them.

Both formulas were read off FPC's `rtl/objpas/math.pp`, not derived, and that
mattered: `RoundTo` DIVIDES by `IntPower(10, digits)` where the natural reading
is to multiply by `10^-digits`. Not cosmetic — `2.675 / 0.01` is
`267.50000000000006` while `2.675 * 100` is `267.49999999999997`, so the first
gives **2.68** and the second **2.67**. FPC says 2.68.

No Extended overloads, deliberately: Extended is aliased to Double and this RTL
targets Single + Double only ([[feature-extended-type-support]]).

## `SetRoundMode` / `GetRoundMode`: the primitive exists, but not for Pascal

This is the one item left, and the ticket's own framing ("a matter of writing
the control word") is right but incomplete. What is actually there:

- `compiler/cparser.inc` already emits `__pxx_fesetround` / `__pxx_fegetround`
  as raw machine stubs, flipping the **MXCSR RC bits [14:13]** — with the note
  that pxx does all double arithmetic in SSE, so MXCSR is the only rounding
  state that matters and there is no x87 use.
- `lib/crtl/include/fenv.h` exposes them to C. quickjs's `js_dtoa` already
  rides `fesetround`.

Two reasons it cannot simply be wrapped from Pascal today:

1. **The intrinsic is C-frontend only** — nothing in `parser.inc` or `lexer.inc`
   knows `__pxx_fesetround`, so Pascal has no way to reach it.
2. **Off x86-64 it is an accepted no-op returning 0** (the
   `EmitCReturnZeroStub` path, which i386 also takes). A Pascal `SetRoundMode`
   built on it would silently do nothing on four of five targets — a
   mode-setter that does not set the mode, which is worse than not having one.

So the remaining work is a Track A/C item — expose the intrinsic to the Pascal
frontend, and implement it for real on the targets that claim it — with the
Pascal `TFPURoundingMode` wrapper landing here afterwards. Filed as
[[feature-a-expose-rounding-mode-intrinsic-to-pascal]].

