---
track: U
prio: 45
type: decide
blocked-by: []
summary: "FPC widens unary minus to 64-bit for EVERY integer type; pxx truncates an UNSIGNED operand to 32 bits first, so `-b shr 1` answers 2147483644 where FPC says 9223372036854775804 — in the DEFAULT dialect, not behind a flag. Adopt FPC's rule as the default, or keep ours and document the divergence?"
---

# Decide: adopt FPC's unary-minus widening in the default dialect

**Read time ~1 minute.** This is the open fork behind
`bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits` (P, p30). That
ticket is complete on its own terms; this decision is what would close the
remaining rows.

## Measured — `var x: T; x := 8; writeln(-x shr 1)`

| T | FPC 3.2.2 | pxx (default AND --strict-fpc) |
| --- | --- | --- |
| Byte | 9223372036854775804 | **2147483644** |
| Word | 9223372036854775804 | **2147483644** |
| Cardinal | 9223372036854775804 | **2147483644** |
| ShortInt / SmallInt / Integer / Int64 | 9223372036854775804 | correct |

The three wrong rows are exactly the UNSIGNED types. `2147483644` is `$7FFFFFFC`
— a 32-bit logical shift of `$FFFFFFF8`, so `-b` was evaluated as unsigned 32-bit
and only then widened. The information is gone before the shift runs.

FPC's rule, measured rather than assumed: `SizeOf(-x)` is **8 for all seven
integer types**.

## Why it is a decision and not just a fix

By the standing rule that the reference implementation decides the default, this
is a plain divergence and pxx is wrong. But unary-minus TYPING has real blast
radius — overflow behaviour, overload resolution, `SizeOf` — so widening `-x`
generally is a language change, not a bug fix.

## Options

1. **Adopt FPC's widening in the default dialect.** Closes the rows; matches the
   reference; changes the type of every `-x` expression in the language.
2. **Keep pxx's rule, document the divergence.** Cheapest; leaves three silently
   wrong answers against FPC in the DEFAULT dialect, which is the part that sits
   badly.
3. **Widen only under `--strict-fpc`.** Splits the behaviour, and the flag
   family is for AMBIGUITY (same source, different meaning) — which this is, so
   it fits — but it leaves the default knowingly wrong.

## PHILOSOPHY ALREADY SETTLES THIS — amended 2026-08-17

Filed as an open fork; on re-reading the stated principles it is not one, and
saying so is the point of this section. Two governing rules apply and both point
the same way:

- **The default is the REFERENCE implementation** (FPC for Track P), with
  deviations behind `--strict-*`. Here the deviation IS the default, which
  inverts the rule.
- **CLAUDE.md's compat escape rule:** *"a compat finding that means silent wrong
  behavior (e.g. an ignored directive producing wrong values) is promoted to a
  normal `bug-` ticket in the owning lane — the tag is for parity work, not a
  place to hide real bugs."* `-b shr 1` answering 2147483644 is a silent wrong
  VALUE, not a laxness.

So this is a **bug**, and option (1) is what the philosophy already requires.
Options (2) and (3) both preserve a known-wrong answer in the mode everyone
uses, which the escape rule exists to forbid.

**What is left for the human is a confirmation, not a decision** — and one real
caveat worth an explicit nod, because the philosophy does not price it: widening
`-x` changes the static TYPE of every unary-minus expression, so overload
resolution and `{$Q+}` overflow behaviour move with it. That is a blast radius
question, not a direction question. Overrule if you want it staged behind a flag
first; otherwise it proceeds as a bug fix.

## Mechanism (for the record, since the *why* is the interesting part)

pxx evaluates `-b` for an unsigned `b` at the operand's own width. `-8` as
unsigned 32-bit is `$FFFFFFF8` = 4294967288. Widening to 64 bits afterwards
ZERO-extends (it is an unsigned type), giving `$00000000FFFFFFF8`, and `shr 1`
then yields `$7FFFFFFC` = 2147483644. FPC widens to Int64 FIRST, so the negation
is exact and the shift sees `$FFFFFFFFFFFFFFF8`. The information is destroyed
before the shift runs, which is why no amount of work in the shift path can fix
it — the ticket this came from established exactly that.

## Original recommendation (unchanged)

**(1).** The default is supposed to be the reference implementation, this is a
silent wrong VALUE rather than a laxness, and options 2 and 3 both preserve a
known-wrong answer in the mode everyone uses. Worth doing deliberately with the
overload-resolution and overflow tests in front of us.

---

## CONFIRMED 2026-08-19 (user) — option (1), as a plain bug fix

User read the 2026-08-17 amendment and agreed it was already decided: *"decide-unary-minus
looks already decided to me."*

**Adopt FPC's widening in the default dialect.** `-x` yields a 64-bit value for every
integer operand type, matching `SizeOf(-x) = 8` across all seven, as measured.

The amendment left exactly one thing open — *"overrule if you want it staged behind a
flag first; otherwise it proceeds as a bug fix"* — and it was NOT overruled. So it lands
as a bug fix in the default dialect, no flag, no staging.

The blast radius stands as stated and is the implementer's problem, not a reopened
direction question: widening `-x` changes the static TYPE of every unary-minus
expression, so **overload resolution and `{$Q+}` overflow behaviour move with it**. Land
it with those tests in front of you, per the original recommendation.

Re-filed into its lane as [[bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits]],
reranked 30 -> 45 to inherit this ticket's priority. A decision that is not re-filed is
invisible to `ready`/`next` and gets rediscovered.

## Log
- 2026-08-19 — confirmed by user, moved to `decided/`.
