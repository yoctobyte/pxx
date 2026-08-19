---
track: D
prio: 30
type: docs
summary: "One backend implements three different, correct rounding rules — Pascal ties-to-even, C half-away-from-zero, Python ties-to-even on the exact decimal — each verified against fpc/gcc/CPython. That is a differentiator and it is documented nowhere; it currently lives only inside a Track B ticket"
---

# Publish the three-language rounding table

- **Type:** docs (Track D — `docs/targets/cross-languages.md`)
- **Status:** backlog — filed 2026-08-09.
- **Owner:** —
- **Related:** [[bug-b-rounding-api-gaps-setroundmode-roundto-lround]]

## Why publish it

The cross-languages page argues that one backend serves several frontends. This
is the sharpest available evidence for that claim being more than plumbing —
the frontends do not merely share a backend, they keep **incompatible
semantics** on the same operation, correctly, at the same time.

Measured 2026-08-09 against each language's own reference on one machine:

| input | 0.5 | 1.5 | 2.5 | 3.5 | -2.5 | rule |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal `Round` (= fpc) | 0 | 2 | 2 | 4 | -2 | ties-to-even |
| C `round()` (= gcc) | 1 | 2 | 3 | 4 | -3 | half-away-from-zero |
| Nil Python `round()` (= CPython) | 0 | 2 | 2 | 4 | -2 | ties-to-even, exact decimal |

Nil Python also matches CPython on the float-repr traps: `round(2.675, 2)` →
`2.67`, `round(1.005, 2)` → `1.0`, `round(0.125, 2)` → `0.12`.

Right now this exists only in a Track B ticket, where nobody reading the docs
will ever find it.

## Shape

A short section on `docs/targets/cross-languages.md` — the table, one paragraph
on why the rows disagree (each language specifies its own rule; C's `round()`
is half-away-from-zero by definition, Pascal's `Round` is a float→int
conversion in the current hardware mode, CPython's is ties-to-even on the exact
decimal value), and the note that making them agree would break all three.

Do **not** oversell it: this is one operation, verified on one machine, on
x86-64. It is not a claim that every numeric edge matches across all three
languages — see the parent ticket for what is missing (`SetRoundMode`,
`RoundTo`, `SimpleRoundTo`, `lround`, `llround`). Claims discipline applies: the
table says what was measured and nothing wider.

## Acceptance

The section is live on pxxc.org, the numbers match a re-run, and the wording
does not generalise beyond the measurement.

## Log
- 2026-08-09 — filed. Measured while checking a user question about whether
  each frontend rounds the way its language expects; the answer was yes for all
  three, which is worth saying out loud.
