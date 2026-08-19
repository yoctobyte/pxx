---
track: A
prio: 30
type: compat
blocked-by: []
summary: "WriteLn/Str of a Single print the value's full Double expansion — 17 significant digits and a 3-digit exponent — where FPC prints 10 digits and a 2-digit exponent: pxx ' 1.0000000149011612E-001' vs FPC ' 1.000000015E-01'. Same class as the FloatToStr(Single) bug fixed in lib/rtl, but this path is the compiler's own float writer, so the RTL cannot reach it. Text-only divergence, no wrong value."
status: done
---

# `WriteLn`/`Str` of a `Single` use Double width

- **Type:** compat (FPC parity, text form) — **Track A** (the float writer
  `WriteLn`/`Str` lower to, in `compiler/builtin/**`; the RTL has no way in).
- Filed by Track B on 2026-08-14 alongside
  [[bug-b-floattostr-of-a-single-prints-15-digits-where-fpc-prints-10]], which
  is the same defect in the half Track B owns and is **fixed**. This is the
  half that is not ours.
- **Prio 30, not 60:** the value is right, only its spelling is wider than it
  should be. Contrast
  [[bug-a-a-single-in-array-of-const-is-boxed-4-bytes-and-read-as-8]], found in
  the same sweep, which returns a number unrelated to the argument.

## Measured — pxx vs FPC 3.2.2

```pascal
var s: Single; d: Double; st: ShortString;
begin
  s := 0.1;
  WriteLn(s);            Str(s, st); WriteLn(st);
  s := 1.0/3.0;
  WriteLn(s);
  d := 0.1;
  WriteLn(d);            Str(d, st); WriteLn(st);
end.
```

| | pxx | FPC |
| --- | --- | --- |
| `WriteLn(Single 0.1)` | ` 1.0000000149011612E-001` | ` 1.000000015E-01` |
| `Str(Single 0.1)` | ` 1.0000000149011612E-001` | ` 1.000000015E-01` |
| `WriteLn(Single 1/3)` | ` 3.3333334326744080E-001` | ` 3.333333433E-01` |
| `WriteLn(Double 0.1)` | ` 1.0000000000000001E-001` | *(same)* |
| `Str(Double 0.1)` | ` 1.0000000000000001E-001` | *(same)* |

The Double rows agree exactly, so the writer itself is right — it is the
**width** that is lost. Two things differ together, and one parameter explains
both: FPC renders a Single with **10 significant digits and a 2-digit
exponent**, a Double with 17 and a 3-digit exponent.

`WriteLn(s:0:2)` and `Str(s:0:4, st)` agree with FPC already — an explicit
width bypasses the default entirely, which is further evidence the defect is
only in the default digit count.

## Why it is worth fixing even though no value is wrong

Printing `1.0000000149011612E-001` claims seventeen digits of a value that has
about seven. It is the machine-readable shape of "this is more precise than it
is", and any recorded expectation or diffed output containing a Single is
different from FPC's for a reason that is not the program's.

## The fix, and the reference implementation to copy

`lib/rtl/sysutils` already solved the same problem the same day: it now declares
two overloads and passes a different significant-digit count to one shared
formatter.

```pascal
function FloatToStr(value: Double): AnsiString;   { FloatToStrSig(value, 15) }
function FloatToStr(value: Single): AnsiString;   { FloatToStrSig(value, 10) }
```

The write path needs the equivalent: keep the argument's static type through the
`WriteLn`/`Str` lowering instead of widening to Double first, and select the
digit count (and exponent width) from it. Establish the exponent-digit rule by
measurement against FPC — it is stated above from a two-value sample, not from
FPC's source.

## Sweep before closing

`Write` as well as `WriteLn`; `Str` with and without width/precision; a Single
**field**, array element and function result, not just a variable; and text-file
output as well as stdout. Also `Extended`, which is aliased to Double here and
so should keep the 17-digit form.

## Gate

The table above matches FPC on every row, the Double rows are unchanged, `make
test` + self-host fixedpoint, and cross — the float writer is per-backend, so a
cross check is not optional here.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.

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
