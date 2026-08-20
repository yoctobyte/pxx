---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`-b shr 1` answers 2147483644 where FPC says 9223372036854775804, for Byte, Word and Cardinal — in BOTH the default dialect and --strict-fpc. FPC's unary minus yields a 64-bit value for EVERY integer operand type (SizeOf(-x) is 8 for all seven, measured); pxx's truncates an unsigned operand to 32 bits before any widening can run, so the sign is already gone."
status: done
owner: frank1-ACP
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

---

## DECIDED 2026-08-19 (user) — fix it, in the DEFAULT dialect, no flag

[[decide-unary-minus-widening-in-the-default-dialect]] is confirmed and closed. The
direction is settled; this ticket is now ordinary Track P work.

**Adopt FPC's rule: unary minus yields a 64-bit value for EVERY integer operand type.**
Not behind `--strict-fpc`, not staged — the default dialect, as a bug fix. The reasoning
is in the decided ticket: the reference implementation sets the default, and
`-b shr 1` answering 2147483644 is a silent wrong VALUE, which the compat escape rule
promotes to a bug rather than parity work.

**Reranked 30 -> 45**, inheriting the decision's priority.

### The one thing to carry into the work

Widening `-x` changes the **static type of every unary-minus expression** in the
language, so two things move with it and neither is optional:

- **overload resolution** — `-x` now selects Int64-taking candidates it previously did not;
- **`{$Q+}` overflow behaviour** — the check now runs at a different width.

Land with those tests in front of you. If either turns out to force a staged rollout
after all, that is a finding worth reporting back, not a reason to re-open the direction.

---

## FIXED 2026-08-20 (frank1-ACP)

All seven table rows now match `fpc -O1` exactly, in the DEFAULT dialect, and so
do the three the table never listed.

### The fix is one line of typing, in `ParseFactor`'s `tkMinus` case

The `AN_NEG` node used to carry the operand's own type (`ASTTk[node] :=
ASTTk[left]`), which is right for a float and wrong for an integer. It now
carries `tyInt64` whenever `NegWidensToInt64` says the operand is an integer
kind — tyInteger, tyChar, tyInt8..tyUInt64, tyNativeInt/tyNativeUInt.
Deliberately excluded: tyBoolean and tyBool8 (not arithmetic), tyPointer (no
sign), the promotable ints (already arbitrary precision, so a width has no
meaning), and every float — where the operand type IS the result type.

Measured first, on the two types the ticket's table omitted plus the aliases:
`SizeOf(-x)` is **8** for QWord, NativeInt, NativeUInt and Char as well. FPC's
unary minus has exactly one result type.

### Both blast-radius items the decision named were checked, and neither bit

- **Overload resolution.** `Pick(b)` selects the `Integer` overload and
  `Pick(-b)` selects the `Int64` one — which is the point, and byte-identical
  to FPC. A `Double` overload is still selected for `-d`.
- **`{$Q+}`.** After the widening, `-Low(Int64)` is the ONLY negation that can
  overflow: every narrower operand widens to Int64 first, where its negation
  always fits. FPC raises `EIntOverflow` there; pxx did not, because unary
  minus was not in the checked set at all — a pre-existing gap that the
  widening made into the last remaining divergence, so it is fixed here too.

  No new IR op and no backend moved: `ir.inc` rewrites a `{$Q+}`-tagged
  `AN_NEG` into `0 - x`, the same rewrite the promotable-int and variant arms
  above it already use, and the existing `IR_BINOP` check does the work.
  `-Byte(200)`, `-Cardinal(4000000000)` and `-Low(Integer)` correctly do NOT
  trap.

### The trap

The **FPC seed canary** caught what the self-host fixedpoint could not:
`NegWidensToInt64` was defined further down `parser.inc` than its call site,
which pxx accepts and FPC does not (`Identifier not found`). A `forward;` next
to `ParseSubroutine`'s fixes it — the same shape as
[[bug-a-fpc-seed-drift-emitasmx64-forward]]. Worth knowing that a helper added
next to its logical neighbours can still be "too late" for the seed.

### Files

- `compiler/parser.inc` — `NegWidensToInt64` (+ its forward), the `tkMinus`
  typing, and the `{$Q+}` tag on the negation node.
- `compiler/ir.inc` — the `0 - x` rewrite for a checked `AN_NEG`.
- `test/test_unary_minus_widens_to_int64.pas` — 31 assertions, all of them FPC
  3.2.2 `-O1`'s own answers (the two programs print the same line). Wired into
  the Makefile beside `test_strict_fpc_shift_widths`, which stays green in both
  modes.

### Left alone, as the ticket said

`SizeOf(-a)` — `SizeOf` of an EXPRESSION — is still `error: SizeOf: expected
type name`; FPC accepts it and answers 8. It is how the widths above were
measured under FPC. Filed now as its own ticket:
[[feature-p-sizeof-of-an-expression]].

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
