---
track: P
prio: 30
type: bug
blocked-by: []
summary: "`-b shr 1` answers 2147483644 where FPC says 9223372036854775804, for Byte, Word and Cardinal — in BOTH the default dialect and --strict-fpc. FPC's unary minus yields a 64-bit value for EVERY integer operand type (SizeOf(-x) is 8 for all seven, measured); pxx's truncates an unsigned operand to 32 bits before any widening can run, so the sign is already gone."
---

# Unary minus on an unsigned operand truncates to 32 bits before the widen

Found 2026-08-16 while fixing
[[bug-p-strict-fpc-narrows-a-negated-integer-shift-the-default-gets-right]].
That ticket measured one row (`a: Integer`) and concluded the DEFAULT dialect
agrees with FPC. Widening the measurement to every integer operand type shows
the default is wrong on three of them, and that is a different defect from the
one that ticket fixed.

## Measured — `var x: T; x := 8; writeln(-x shr 1)`

| T | FPC 3.2.2 -O1 | pxx default | pxx --strict-fpc |
| --- | --- | --- | --- |
| Byte | 9223372036854775804 | **2147483644** | **2147483644** |
| ShortInt | 9223372036854775804 | 9223372036854775804 | 9223372036854775804 |
| Word | 9223372036854775804 | **2147483644** | **2147483644** |
| SmallInt | 9223372036854775804 | 9223372036854775804 | 9223372036854775804 |
| Integer | 9223372036854775804 | 9223372036854775804 | 9223372036854775804 |
| Cardinal | 9223372036854775804 | **2147483644** | **2147483644** |
| Int64 | 9223372036854775804 | 9223372036854775804 | 9223372036854775804 |

(The `--strict-fpc` column is post-fix; before that fix only Int64 was right.)

The three wrong rows are exactly the UNSIGNED types. `2147483644` is
`$7FFFFFFC` — a 32-bit logical shift of `$FFFFFFF8`. So `-b` was evaluated as an
unsigned 32-bit value (`4294967288`) and only then widened; zero-extending that
gives `$00000000FFFFFFF8`, and shifting it right by one gives `$7FFFFFFC`. The
information is lost before the shift ever runs, which is why the shift path is
not where this can be fixed.

FPC's rule, measured rather than assumed: `SizeOf(-x)` is **8 for all seven
types**, including `Byte` and `Cardinal`. Its unary minus widens to Int64 first
and the negation is exact.

## Why this is filed separately

1. It is in the DEFAULT dialect, not just behind a flag, so by the standing rule
   that the reference implementation decides the default it is a plain
   divergence — not a dialect choice.
2. It is unary-minus TYPING, whose blast radius (overflow behaviour, overload
   resolution, `SizeOf`) is exactly what the parent ticket flagged as needing the
   owner's call before anyone widens `-x` generally. That call is still open:
   the parent's option **(3)** — adopt FPC's unary-minus widening in the default
   dialect — is what would fix these rows, and it was deliberately not taken.
3. The parent ticket is complete on its own terms (`--strict-fpc` no longer
   disagrees with FPC where the default agrees) and should not be held open for
   this.

So this ticket is really "resolve the parent's option (3), for the rows where
the default is visibly wrong". Worth pairing with the owner decision rather than
picked up cold.

## Side finding, inherited from the parent ticket

`SizeOf(-a)` — `SizeOf` of an EXPRESSION — is `error: SizeOf: expected type
name` in pxx; FPC accepts it and answers 8. It is how the widths above were
measured (under FPC). Still not filed on its own; still not part of this bug.

## Gate

The table above matching `fpc -O1` row for row in whichever mode the decision
picks, with `test/test_strict_fpc_shift_widths.pas` staying green in BOTH modes;
`gate.sh quick`; self-host fixedpoint.
