---
track: B+F
prio: 15
type: bug
blocked-by: []
summary: "Fixed-point rendering of a decimal tie rounds the OTHER WAY from FPC: Format('%.2f', [1.005]) is 1.00 here and 1.01 there, likewise 2.675 -> 2.67 vs 2.68. Ours is the correctly-rounded answer for the actual Double (1.005 is 1.00499999999999989); FPC rounds the decimal literal as written. Pre-existing in FmtFixed, so it hits '%f', '%n', '%m' and FloatToStrF's ffFixed/ffNumber/ffCurrency alike. Last-digit-only — Track F by definition."
status: backlog
owner: unassigned
---

# A decimal tie rounds down here, up in FPC

Found 2026-08-25 by Track B while adding FPC's four-argument `FloatToStrF`
(`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`). **Not introduced by
that work** — the same divergence is already reachable through `Format('%.2f')`,
which has been in `lib/rtl/sysutils.pas` all along. Nineteen of the twenty
FloatToStrF cases in that ticket's probe are byte-identical to FPC; this is the
twentieth.

## Measured (fpc 3.2.2 vs pxx pinned stable, LC_ALL=C)

| expression | FPC | pxx |
| --- | --- | --- |
| `Format('%.2f', [1.005])` | 1.01 | **1.00** |
| `Format('%.2f', [-1.005])` | -1.01 | **-1.00** |
| `Format('%.2f', [2.675])` | 2.68 | **2.67** |
| `Format('%.2f', [0.125])` | 0.13 | 0.13 (agree) |

Same three rows through `FloatToStrF(v, ffFixed, 15, 2)`, and they will show up
in `ffNumber` and `ffCurrency` too, since all four route through `FmtFixed`.

## Which one is right

Arguably ours. `1.005` is not representable: the nearest Double is
1.00499999999999989341858963598497211933135986328125, which is BELOW the tie, so
1.00 is the correctly-rounded two-place rendering of the value that actually
exists. FPC reaches 1.01 by rounding a decimal intermediate rather than the
binary value.

`0.125` agrees because it IS exactly representable, so both implementations see a
genuine tie and both round half-away-from-zero on it.

So this is not "we are wrong", it is "we round the value and FPC rounds the
literal". Worth knowing before anyone changes it *toward* FPC and makes the
other cases worse.

## Why it is Track F and not an ordinary bug

The subject is float RENDERING, and the disagreement is confined to the last
digit — exactly the "insignificant digits" case the owner named. Nothing is
missing, nothing crashes, no signature is wrong. Per CLAUDE.md's F rule this
parks in `float/` and is not ranked.

The escape hatch does not apply: nobody is getting a silently wrong ANSWER, only
a differently-rounded last digit of a printed one.

## If it is ever picked up

The fix is in `FmtFixed` (`lib/rtl/sysutils.pas`), and it is one decision:
whether the rounding happens on the exact decimal expansion of the Double (as
`ExDecDigits`/`ExDecRound` already do for `FmtExponent`) or on a scaled
intermediate. `FmtExponent` was rewritten onto the exact path for a related
reason and its note records what that bought; `FmtFixed` was not.

## Gate

Track B: `make lib-test`, plus the four rows above compared against
`fpc -O- -Mobjfpc -Sh` output for the same program.
