---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Format('%g', [aSingle]) returns 5.122630465115234E-315 where FPC gives 0.10000000149011612, and '%.4f' gives 0.0000 instead of 0.1000. compiler/ir.inc boxes an array-of-const element in a local of the ELEMENT's type, so a Single gets a 4-byte box, but it tags it vtExtended and every consumer dereferences 8 bytes. Confirmed arithmetically: the printed value is exactly Single(0.1)'s bit pattern read as the low half of a double. Silent garbage from any Format of a Single."
status: done
owner: agent-AN
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

## Resolution

The ticket's diagnosis was right in full, including the arithmetic. Fixed where
it said: `compiler/ir.inc`, at the box, not at the reader.

```pascal
vrBoxTk := vrElemTk;
if vrBoxTk = tySingle then vrBoxTk := tyDouble;
vrBoxSym := AllocVar('', vrBoxTk);
```

...and the `IR_STORE_MEM` carries `Ord(vrBoxTk)` too, so the store's DEST type
performs the widening — the same mechanism the 32-bit C vararg promotion a few
thousand lines up already relies on ("the store-to-double slot keeps the value
double-wide"). No consumer changed, and the `vtExtended` tag is now honest.

### Measured against FPC 3.2.2

| | before | after | FPC |
| --- | --- | --- | --- |
| `%g` | 5.122630465115234E-315 | 0.10000000149011612 | 0.10000000149011612 |
| `%.4f` | 0.0000 | 0.1000 | 0.1000 |
| `%e` | 5.1226304651152340E-315 | 1.0000000149011612E-001 | 1.0000000149011612E-001 |

### The sweep the ticket asked for

- **Other shapes** — variable, record FIELD, array ELEMENT, and an expression
  (`s * 2`): all correct. The width came from one place, so one fix covered
  them.
- **Other consumers** — `FmtArgStr` (`%s` of a Single → `2.5`) and `FmtArgInt`
  (`%d` → `3`, the truncation, where it was garbage before).
- **Adjacent boxes** — two Singles in one call, and a Single beside a Double
  and an Int64, all read back distinct and correct. This was the failure mode
  worth checking: the old 4-byte box read its NEIGHBOUR.
- **`tyExtended`** takes the same branch and is unchanged — Extended is aliased
  to Double here, so its box was already 8 bytes. Left alone deliberately.
- **Every backend** — the box is a stack local, so each target was run, not
  reasoned about. `i386`, `aarch64`, `arm32`, `riscv32` under qemu are all
  **byte-identical to x86-64** on the full sweep.

### One divergence, pre-existing and NOT touched

`Format('%d', [aSingle])` prints `3` here; FPC raises
`EConvertError: Invalid argument index`. That is a laxness in `FmtArgInt`, not
this bug — before the fix the same line printed a garbage integer, so the fix
strictly improved it. Out of scope for a boxing ticket; it belongs to the
sysutils Format compat surface if anyone wants FPC's refusal.

### Tests

- `test/test_format_single_arg.pas` (new) — all nine lines byte-identical to
  FPC 3.2.2, wired into the Makefile with an inline expectation.
- `test/test_array_of_const_types.pas` extended with a Single, which pins the
  BOX WIDTH directly rather than through Format: it reads the raw `TVarRec`
  and derefs `PD(items[i].VExtended)^`. That test already runs as an i386
  differential against x86-64, so the cross coverage comes free and permanently.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary), plus the four cross targets run under qemu above. `compiler/builtin/**`
untouched, so no re-pin.

### Method note

The first cross-target comparison looked like all four targets DIFFERED. They
did not: building the repro with FPC in the scratch directory had overwritten
the pxx binary of the same name, so "native" was FPC's build raising its
EConvertError. Name the oracle's binary differently — the provenance rule
applies to the reference build too, not only to the compiler under test.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
