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

## Recommendation

**(1).** The default is supposed to be the reference implementation, this is a
silent wrong VALUE rather than a laxness, and options 2 and 3 both preserve a
known-wrong answer in the mode everyone uses. Worth doing deliberately with the
overload-resolution and overflow tests in front of us.
