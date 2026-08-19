---
summary: "write(r:W) with a width but no decimals ignores W entirely — pxx always prints the full 16-decimal scientific form where FPC sizes the mantissa to the field"
type: bug
prio: 20
track: A
status: done
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

## 2026-08-19 — FIXED. One change, two tickets: the sci writer took no parameters.

Fixed together with [[bug-b-write-of-a-real-ignores-the-field-width-without-decimals]]
because they are one bug. The evidence is a signature, not a resemblance:

```pascal
PXXWriteFloatFixed(p: Pointer; decimals: NativeInt; width: NativeInt)   { takes both }
PXXWriteFloatSci  (p: Pointer)                                          { took neither }
```

`PXXWriteFloatSci` hardcoded 16 fractional digits and a 3-digit exponent, so
*every* request to format a scientific float differently was unrepresentable —
a `Single` asking for its 10-significant-digit/2-digit-exponent form, and
`write(d:W)` asking to narrow the mantissa to the field, are the same missing
parameterisation seen from two sides.

### The second half was in a different file

Even a corrected emitter would have failed. `compiler/parser.inc:35993`
**pre-registers** the helper so `FindProc` can resolve it before `builtinheap`
parses, and it declared **one** parameter — passing more gives
`unresolved forward: PXXWriteFloatSci`. Two places had to agree and both said
"one argument", so anyone re-deriving this from the emitter alone would conclude
the emitter was the whole story.

### The rule, measured against FPC 3.2.2 rather than derived from docs

`SciFormatFor(wid, tk, ...)` in `symtab.inc` holds it once, with this table in
its comment — five copies of the clamp is where an off-by-one hides:

| | FPC | pxx now |
| --- | --- | --- |
| `d` | ` 3.3333333333333331E-001` | ok |
| `d:12` | ` 3.3333E-001` | ok |
| `d:20` | ` 3.333333333333E-001` | ok |
| `d:8` | ` 3.3E-001` | ok |
| `s` | ` 3.333333433E-01` | ok |
| `s:14` | ` 3.3333334E-01` | ok |

`frac = wid - 5 - expdigits`, clamped to >= 1, `expdigits` 3 for Double / 2 for
Single. FPC's floor is one fractional digit and it **overflows the field**
rather than going below it (`d:8` prints nine characters), so a narrow width
widens the output instead of truncating the number.

### The near-miss, which was not the clamp

The five backends inferred *"does this writer take arguments?"* from
`decs >= 0`. That was exact **only because `PXXWriteFloatNat` and
`PXXWriteFloatSci` were both called with -1**. Once Sci carries real arguments
the inference is wrong, and wrong identically in all five. My first edit used
`decs <> -2` and would have passed `Nat` two arguments it does not take, in
every backend at once.

> **A derived discriminator that happens to be correct is indistinguishable from
> one that is correct by construction, until the thing it was derived from
> changes.**

Each backend now takes an explicit `passArgs: Boolean`, which *records* the fact
instead of re-deriving it from a coincidence.

Two duplications removed while there rather than after: aarch64's sci emitter was
repeating `EmitFloatCallWriterA64`'s spill/call/restore inline (invisible while
the path passed no arguments, two copies to fix the moment it did), and the
format rule exists once rather than per-backend.

### Verified

- Six FPC rows above: all match, on **all five backends**, byte-identical to
  each other (native x86-64/i386, qemu for aarch64/arm32/riscv32).
- `make compiler/pascal26` clean — self-host fixedpoint holds.
- `tools/gate.sh quick` **GREEN** (fixedpoint 47s, testmgr quick, FPC canary).
- Untouched by design: the fixed-form huge magnitude still prints the exact
  expansion, per [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]].

### Measuring caveat for anyone re-running this

FPC constant-folds `1.0/3.0` at **Single** precision, so a probe using literal
constants reads as a pxx bug for an hour. Compute the value from runtime
variables. Caught here only because the digits were recognisably float32's.

## Log
- 2026-08-19 — resolved, commit 354f734c1.
