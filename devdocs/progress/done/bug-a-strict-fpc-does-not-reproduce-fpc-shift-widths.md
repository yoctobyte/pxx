---
track: A
prio: 30
type: bug
blocked-by: []
status: done
owner: claude-A
---

# `--strict-fpc` does not reproduce FPC's shift widths

- **Type:** bug (an advertised strict mode that is not strict) — **Track A**
- **Opened:** 2026-08-11, completing
  [[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]].

[[decide-shift-operator-promotion-width]] has two halves. The default half —
shifts at NATIVE width, no truncation — landed. The other half did not:

> "**`--strict-fpc`: reproduce FPC exactly**, asymmetry and all — `shr` widens
> the operand to 64, `shl` masks the count to 5 bits at 32-bit width, and the
> constant folder keeps its own 64-bit answer. Explicitly 'copy their bugs'."

Today `--strict-fpc` shifts exactly like the default dialect, so the escape
hatch the decision promised anyone porting FPC bit-twiddling does not exist.

## What it has to reproduce (measured, `fpc 3.2.2 -O1 {$mode objfpc}`)

| row | FPC | pxx default |
| --- | --- | --- |
| `i shr 1`, `i: Integer = -8` | 2147483644 | 9223372036854775804 |
| `i shl 31`, `i: Integer = 1` | -2147483648 | 2147483648 |
| `l shr 9`, `l = -2147483648` | 4194304 | 36028797014769664 |
| `l shl 1`, `l = -2147483648` | 0 | -4294967296 |
| `a shl b` (8 shl 40, both vars) | 2048 (count masked mod 32) | 8796093022208 |
| `1 shl 40` (const fold) | 1099511627776 | 1099511627776 |
| `-8 shr 1` (const fold) | 9223372036854775804 | 9223372036854775804 |

Note the last two: FPC's own constant folder does NOT mask or narrow, so strict
mode must keep the fold at 64 bits while the runtime path narrows — the
asymmetry the decision means by "copy their bugs".

## Where the code is

The width choice is one place now: the shift arm of the binop typing in
`parser.inc` (`op = tkIdent` / `tkShl`) decides the RESULT type, and both
backends' shift emitters obey it — a narrow result narrows, an 8-byte result
does not. So strict mode is that arm keeping `ASTTk[left]`, plus the count-mask
for `shl`, which no backend emits today.

## Gate

Every row above matching `fpc -O1` under `--strict-fpc`, the default dialect
unchanged (`test/test_shr_width.pas`, `test/test_shift_operand_width.pas`), and
self-host byte-identical.

## Resolution (2026-08-11) — 9 of the 10 rows; the 10th is not a shift

`StrictShiftWidth` joins the `--strict-fpc` umbrella and reproduces FPC's shift
behaviour including the contradiction the decision meant by "copy their bugs":

- a shift over a VARIABLE keeps the operand's declared width — the typing arm
  simply does not promote under the flag;
- `shl` masks its count to 5 bits, so `8 shl 40` is 2048. Implemented by
  emitting the 32-BIT shift (`shl eax, cl` / `lsl w0, w0, w1`) rather than an
  explicit mask: the hardware already masks the count at that width, and the
  existing narrow-back then applies unchanged. Both 64-bit backends, gated on
  the operand AND the result being narrow — without the second test the
  constant-fold rows masked too and `1 shl 40` came out 256;
- the constant FOLDER keeps full width for both operators, matching FPC's own
  inconsistency. A literal left operand — including a NEGATED one, which is a
  separate AST shape — still promotes under the flag.

Every row of the ticket's table matches `fpc -O1` except one, and that one is
**not a shift divergence**: `-a shr 1` over an Integer variable. FPC answers
9223372036854775804 because its UNARY MINUS on an Integer yields Int64, so the
shift already sees 64 bits — measured directly (`-a` prints -8 in both, but
FPC's carries the wider type). Reproducing it means adopting FPC's unary-minus
widening, which is a different semantic with its own blast radius and does not
belong under a shift flag. **Left open as that one row.**

The DEFAULT dialect is byte-for-byte unchanged — asserted in the Makefile by
running the same file both with and without the flag and expecting the two
different answer sets.

New `test/test_strict_fpc_shift_widths.pas`, matching `fpc -O1` row for row on
x86-64 and aarch64. A 64-bit-target test by construction: "native width" is 32
bits on i386/arm32/riscv32, so the full-width rows cannot hold there and do not
under the default dialect either. `gate.sh quick` GREEN (self-host
byte-identical).


## RESOLVED 2026-08-16 — closed; the one open row re-filed where it belongs

Every row of the table matches `fpc -O1` under the flag except `-a shr 1` over
an Integer VARIABLE, and that row was left open here on the grounds that it "is
not a shift divergence". Re-measured today, and the consequence is sharper than
this ticket recorded:

| | `-a shr 1`, `a: Integer = 8` |
| --- | --- |
| FPC 3.2.2 `-O1` | 9223372036854775804 |
| pxx **default** | 9223372036854775804 — **matches** |
| pxx `--strict-fpc` | 2147483644 — **diverges** |

So this is not "a row we cannot reach". It is the one row where turning ON the
reproduce-FPC-exactly flag makes the answer LESS like FPC, while the default
dialect already agrees. That inverts what a user would assume the flag does, and
it is a different fault from the one this ticket is about (shift widths): the
cause is that FPC's unary minus on an Integer yields Int64, so its operand is
already 64 bits before any shift rule applies.

Re-filed as [[bug-p-strict-fpc-narrows-a-negated-integer-shift-the-default-gets-right]]
so it is ranked as what it is — a unary-minus typing question with its own blast
radius — rather than sitting behind a shift ticket that is otherwise finished.

The shift work itself is complete and gated: `test/test_strict_fpc_shift_widths.pas`
matches `fpc -O1` row for row on x86-64 and aarch64, and the Makefile asserts the
DEFAULT dialect is byte-for-byte unchanged by running the same file with and
without the flag.
