---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Format('%g', [aSingle]) returns 5.122630465115234E-315 where FPC gives 0.10000000149011612, and '%.4f' gives 0.0000 instead of 0.1000. compiler/ir.inc boxes an array-of-const element in a local of the ELEMENT's type, so a Single gets a 4-byte box, but it tags it vtExtended and every consumer dereferences 8 bytes. Confirmed arithmetically: the printed value is exactly Single(0.1)'s bit pattern read as the low half of a double. Silent garbage from any Format of a Single."
---

# A `Single` in `array of const` is boxed as 4 bytes and read as 8

- **Type:** bug (silent wrong value) — **Track A** (`compiler/ir.inc`, the
  `array of const` lowering). Filed by Track B on 2026-08-14 during a
  differential sweep of `lib/rtl`'s float rendering against FPC 3.2.2.
- **Not a rendering nicety.** The other two findings from that sweep are about
  how many digits a `Single` prints; this one returns a number that has nothing
  to do with the argument.

## Measured — pxx vs FPC 3.2.2

```pascal
var s: Single;
begin
  s := 0.1;
  WriteLn(Format('%g',   [s]));
  WriteLn(Format('%.4f', [s]));
  WriteLn(Format('%e',   [s]));
end.
```

| | pxx | FPC |
| --- | --- | --- |
| `%g` | **5.122630465115234E-315** | 0.10000000149011612 |
| `%.4f` | **0.0000** | 0.1000 |
| `%e` | **5.1226304651152340E-315** | 1.0000000149011612E-001 |

A `Double` argument is correct on every one of these, so it is the `Single`
path alone.

## Cause — confirmed by arithmetic, not by reading

`compiler/ir.inc` (~5088), lowering `array of const`:

```pascal
else if (vrElemTk = tySingle) or (vrElemTk = tyDouble) or (vrElemTk = tyExtended) then
  vrTag := 3             { vtExtended (boxed) }
...
vrBoxSym := AllocVar('', vrElemTk);      { <-- box is the ELEMENT's width }
```

The tag says `vtExtended`, and every consumer honours that —
`lib/rtl/sysutils`'s `FmtArgFloat`/`FmtArgStr`/`FmtArgInt` all do
`PDoubleRec(v.VExtended)^`, an **8-byte** read. But `AllocVar('', tySingle)`
gives a **4-byte** box. So the reader takes the Single's 4 bytes plus 4 bytes of
whatever sits next to it.

Verified numerically rather than assumed:

```
Single(0.1) bits                        = 0x3DCCCCCD
those 32 bits as the low half of a double = 5.122630465e-315
pxx printed                               = 5.122630465115234E-315   ← identical
```

The neighbouring 4 bytes happened to be zero here, which is why the result is a
stable denormal rather than obvious noise — and why this can look reproducible
and harmless while being whatever is adjacent on the stack.

## The fix

Widen at the box, not at the reader: when `vrElemTk = tySingle`, allocate the
box as `tyDouble` and store the widened value. FPC does the same thing — it has
no `vtSingle` at all, every float goes in as `VExtended` — so the tag stays
right and no consumer changes.

Fixing it in the RTL instead is not possible: `vtExtended` is the only float tag
there is, so the reader cannot tell a 4-byte box from an 8-byte one. (`FmtArgIs32`
recovers the original width for *integers*, but only because `vtInteger` and
`vtInt64` are distinct tags. Floats have no such pair, by FPC's design.)

## Sweep before closing

- Every consumer of `array of const`, not just `Format`: `FmtArgStr`,
  `FmtArgInt` (which does `Trunc(PDoubleRec(...)^)` — a Single argument there
  yields a garbage integer), fpjson's `TJSONArray.Create`, and the asm-text
  emitters that build `%`-hole vectors.
- `tyExtended` takes the same branch. Extended is aliased to Double in this
  RTL, so it is probably fine today, but it is the same line.
- A `Single` **field or array element** passed through, not just a variable, in
  case the width comes from a different place there.
- Each backend: the box is a stack local, so 32-bit targets are worth a look on
  their own.

## Gate

The table above matches FPC, plus a Single through `%d`-style integer
conversions and through a non-Format consumer. `make test` + self-host
fixedpoint, and cross.
