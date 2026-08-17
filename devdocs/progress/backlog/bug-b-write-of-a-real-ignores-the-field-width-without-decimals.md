---
summary: "write(r:W) with a width but no decimals ignores W entirely — pxx always prints the full 16-decimal scientific form where FPC sizes the mantissa to the field"
type: bug
prio: 20
track: A
---

# `write(r:W)` ignores the field width when no decimals are given

- **Type:** bug (Write formatting — mechanical, low prio per the float-handling
  rule). Owning lane B (runtime formatting), but the emitter is compiler ground:
  `EmitWriteFloatSci` (`compiler/symtab.inc:7359`, plus the per-backend siblings
  e.g. `EmitWriteFloatSciA64`) takes **no width argument at all**, and
  `IR_WRITE` in `compiler/ir_codegen.inc:4710` drops `wid` on that path.
  A `compiler/builtin` change needs `make stabilize-fast && make pin`.
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (Write
  formatting topic). The `:W:D` fixed path is fine — `EmitWriteFloatFixed(wid,
  decs)` honours both — and so is every integer/string/char/boolean width. Only
  the real-with-width-but-no-decimals form is wrong.

## Symptom

```pascal
var d: double; begin d := 1.5; writeln(d:5, '|') end.
```

| | output |
| --- | --- |
| FPC | ` 1.5E+000\|` |
| pxx | ` 1.5000000000000000E+000\|` |

pxx prints the identical 22-char string for every width from `:1` to `:26`; the
field is neither shrunk nor padded.

## FPC's rule (measured, `double` and `single` variables)

Scientific form is `<sign><digit>.<decimals>E<expsign><expdigits>`, where the
exponent field is **3** digits for `double`, **2** for `single`, **4** for
`extended` (an untyped real *constant* passed straight to `write` is extended,
which is why a literal probe shows 4 — use variables when checking this).

Decimals are chosen from the requested width and clamped to the type's
precision:

- `double`: `decimals = clamp(W - 8, 1, 16)` — so `W <= 9` gives the minimum
  form `1.5E+000` (9 chars incl. the leading sign position), `W = 17` gives
  `1.500000000E+000`, `W >= 25` saturates at 16 decimals and **pads on the
  left** (`W = 26` -> two leading spaces).
- `single`: `decimals = clamp(W - 7, 1, 7)` — minimum ` 1.5E+00` at `W <= 8`,
  saturating at 7 decimals by `W = 14`.

The exponent grows past its type width when the value needs it (`1e-300` ->
`E-300` in a double's 3-digit field is exact; a 4-digit exponent appears for
extended).

## Fix sketch

Give `EmitWriteFloatSci` the width the way `EmitWriteFloatFixed` already has it:
thread `wid` through `IR_WRITE`, derive the decimal count with the clamp above
from the value's float kind, and left-pad to `W`. Six backends have their own
copy of this emitter — grep `WriteFloatSci` and fix them together, or the
divergence just moves to the cross targets (`devdocs/dev/normalise-dont-special-case.md`).

## Gate

A probe sweeping `writeln(d:i)` for `i` in 1..26 against `fpc -O- -Mobjfpc`,
for `single` and `double`, matches byte for byte; `gate.sh quick` GREEN. Add it
as `test/test_write_real_width.pas` with FPC's output as `.expected`.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.

## 2026-08-17 (frank3) — NOT WORKED. Symptom re-measured and the title is now wrong.

Claimed, measured, then **released unworked** on the standing rule that float
work (accuracy, ULP, rounding, range, *and formatting*) stays low priority. No
code changed. Recording the measurement because the body above is stale in a way
that would mislead whoever picks this up.

Measured against `pinned` **v344** vs `fpc -O- -Mobjfpc`.

### The title and symptom are both out of date

> *"`write(r:W)` ignores the field width"* / *"pxx prints the identical 22-char
> string for every width from `:1` to `:26`; the field is neither shrunk nor
> padded."*

**Both halves are false today.** The width IS honoured — pxx pads correctly, and
the output changes with every `W`:

| `writeln(d:W)`, d = 1.5 | pxx v344 | FPC 3.2.2 |
| --- | --- | --- |
| `:1` | `1.5` | ` 1.5E+000` |
| `:6` | `   1.5` | ` 1.5E+000` |
| `:12` | `         1.5` | ` 1.5000E+000` |
| `:26` | `                       1.5` | `   1.5000000000000000E+000` |

So the divergence is not width handling at all, it is the **FORM**: pxx prints
the natural shortest decimal right-aligned in the field, FPC prints scientific
with the decimal count derived from the width. A retitle is part of the fix.

Mechanically, `ir_codegen.inc:4710` dispatches `decs = -2` to `EmitWriteFloatNat`
(natural decimal, trailing zeros trimmed) and only `decs = -1` to
`EmitWriteFloatSci`. The `:W`-with-no-decimals form is reaching the **Nat** path,
which is why it is short and padded rather than scientific and unpadded. The
ticket's "`IR_WRITE` drops `wid`" is therefore also not what is happening.

### FPC's rule, measured rather than inferred

`decimals = clamp(W - 8, 1, 16)` for `double`, `clamp(W - 7, 1, 7)` for `single`,
confirmed on more than the 1.5 case:

```
neg  :09[-1.5E+000]   neg  :12[-1.5000E+000]     { sign occupies the lead slot }
e300 :08[ 1.0E-300]   e300 :12[ 1.0000E-300]     { 3-digit exponent stays exact }
zero :08[ 0.0E+000]   zero :12[ 0.0000E+000]     { zero takes the same shape }
third:08[ 3.3E-001]   third:14[ 3.333333E-001]   { rounds, does not truncate }
sthrd:06[ 3.3E-01 ]   sthrd:12[ 3.33333E-01]     { single: 2-digit exponent }
```

### Where the fix lives — and why it is not Track B's to make

`PXXWriteFloatSci(p: Pointer)` in **`compiler/builtin/builtinheap.pas`** takes no
width, and the per-backend emitters (`ir_codegen.inc`, `_aarch64`, `_arm32`,
`386`, `_riscv32`) each call it. So the change is `compiler/**` plus
`compiler/builtin/**` — which **needs `make stabilize-fast && make pin`**, and a
pin holds a repo-wide lock and belongs to the coordinator.

The frontmatter says `track: B` and the body says "owning lane B (runtime
formatting)". That is not where the code is: there is no `lib/rtl` component to
this at all. Left as filed rather than re-tracked unilaterally, but whoever
schedules it should treat it as **Track A work with a pin**, not a library fix.

### Gate, ready to use

The probe is written and reproduces cleanly — `writeln(d:i)` for `i` in 1..26 and
`writeln(s:i)` for 1..16, diffed against `fpc -O- -Mobjfpc`. 42 of 42 lines
differ today. Deliberately **not** added to `test/` as an unwired or red test:
this repo already has tests that exist and run nowhere, and adding a red one to
the gate for a fix that has not landed is the same failure wearing the other hat.


## Re-tracked B -> A by the coordinator, 2026-08-17

Track B measured it and handed the routing up rather than re-tracking unilaterally,
which is the right split: a worker reports what it found, the coordinator moves the
lane.

`PXXWriteFloatSci` lives in `compiler/builtin/builtinheap.pas` and five backend
emitters call it. **There is no `lib/rtl` component at all**, so this cannot be
worked under Track B's gate — and `compiler/builtin/**` needs a **pin**, which is
coordinator-scheduled. The `B` in the slug is now wrong; the frontmatter is what
the ranker reads, so the slug is left alone rather than churned.

Priority unchanged and deliberately low: float work is low priority by standing
ruling (accuracy, ULP, rounding, range **and formatting**). Re-tracking is about
who *can* do it, not about it becoming more important.
