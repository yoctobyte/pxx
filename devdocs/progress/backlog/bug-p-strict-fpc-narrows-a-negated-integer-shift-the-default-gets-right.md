---
summary: "`--strict-fpc` answers 2147483644 for `-a shr 1` where FPC — and pxx's own DEFAULT dialect — both say 9223372036854775804: the reproduce-FPC flag is the only mode that gets this row wrong"
type: bug
prio: 25
track: P
---

# `--strict-fpc` narrows a negated-Integer shift that the default gets right

- **Type:** bug (dialect flag / unary-minus typing) — Track P, shared
  `parser.inc`.
- **Status:** backlog. Re-filed 2026-08-16 out of
  [[bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths]], which is otherwise
  complete; this row was parked inside it as "not a shift divergence", which is
  correct and is exactly why it needed its own ticket.

## Measured

```pascal
{$mode objfpc}
var a: Integer;
begin a := 8; writeln(-a shr 1); end.
```

| | result |
| --- | --- |
| `fpc 3.2.2 -O1` | `9223372036854775804` |
| pxx **default** | `9223372036854775804` — matches |
| pxx `--strict-fpc` | `2147483644` — diverges |

## Why it is worth a ticket rather than a footnote

A flag documented as "reproduce FPC exactly, asymmetry and all" is the ONE mode
that disagrees with FPC here, while the mode that makes no such promise agrees.
Anyone reaching for `--strict-fpc` while porting FPC bit-twiddling — the exact
audience it exists for — is handed a worse answer than if they had left it off.

## Cause, and why it is not a shift fix

FPC's **unary minus on an Integer yields Int64** (`-a` prints -8 in both, but
FPC's carries the wider type; `SizeOf(-a)` is 8 under FPC). So FPC's operand is
already 64 bits and no shift rule is involved. pxx types `-a` as Integer, and
`--strict-fpc`'s narrow-shift arm — deliberately gated on the operand AND the
result being narrow — then fires correctly on a premise that differs from FPC's.

The narrow arm is right. The operand type is what differs, so a fix belongs in
unary-minus typing, not in the shift path.

## The decision this needs first

Adopting FPC's unary-minus widening wholesale changes the type of every `-x`
over an Integer, which reaches overflow behaviour, overload resolution and
`SizeOf` — a blast radius well beyond this row. Three options, in increasing
cost:

1. **Leave it**, and document `--strict-fpc` as not covering unary-minus width.
   Cheapest, and honest, but leaves the flag wrong on a row it visibly touches.
2. **Widen only under `--strict-fpc`**, so the flag's own premise matches FPC's
   before its narrow-shift arm runs. Contained to the strict path, which is
   where the promise lives.
3. **Adopt it in the default dialect too.** Most FPC-faithful, largest blast
   radius, and the one that needs the owner's call.

Recommendation: **(2)**. The flag is where the "copy their bugs" promise was
made, so the premise it reasons from should be FPC's premise; the default keeps
pxx's own simpler rule and — as measured above — already produces FPC's answer
on this row anyway.

## Gate

The probe above matching `fpc -O1` in whichever mode the decision picks, plus
the existing `test/test_strict_fpc_shift_widths.pas` staying row-for-row green;
`gate.sh quick`; self-host fixedpoint.

## Side finding (unrelated, not filed on its own)

`SizeOf(-a)` — SizeOf of an EXPRESSION — is `error: SizeOf: expected type name`.
FPC accepts it and answers 8. Noted here because it is how the type above was
measured; it is not part of this bug.
