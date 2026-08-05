---
summary: "writeln(Double) and Str(F,S) scale by repeated /10.0 and are wrong from the 16th digit; 1e200 even gets the wrong EXPONENT"
type: bug
track: A
prio: 60
owner: claude-A
---

# `writeln` of a Double is not correctly rounded (and `Str` disagrees with it)

- **Type:** bug — Track A (`compiler/builtin/builtin.pas`)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, `tools/fpc_diff_probe.sh` `real-default` case, chased
  past the Extended-vs-Double confound that had made it look like a type
  difference.

## Symptom

Both operands are a **`Double` variable** in every row below — the confound
that hides this is that FPC types a bare real literal as `Extended`, so a
careless comparison blames the type and stops.

| value | pxx `writeln` | FPC | CPython |
| --- | --- | --- | --- |
| `1e30` | 1.0000000000000004E+030 | 1.0000000000000000E+030 | 1.0000000000000000e+30 |
| `1e100` | 1.0000000000000007E+100 | 1.0000000000000000E+100 | 1.0000000000000000e+100 |
| **`1e200`** | **1.0000000000000007E+200** | 9.9999999999999997E+199 | 9.9999999999999997e+199 |
| `1e-20` | 1.0000000000000007E-020 | 9.9999999999999995E-021 | 9.9999999999999995e-21 |
| `123456789012345.0` | 1.2345678901234503E+014 | 1.2345678901234500E+014 | 1.2345678901234500e+14 |
| `2.5e100` | 2.5000000000000018E+100 | 2.4999999999999999E+100 | 2.4999999999999999e+100 |

FPC and CPython agree on every row; pxx is wrong on every row. The `1e200` row
is the worst: the **exponent** is wrong, not just the digits — the value is
just under 1e200 and prints as if it were just over.

`Str(F, S)` with no width goes through the same routine's sibling branch and
gives yet a third answer — `1.0000000000000006E+100`, differing from `writeln`'s
`...007`. Two spellings of the same conversion in one file, disagreeing.

## Root cause

`compiler/builtin/builtin.pas`, the `width < 0` branch:

```pascal
m := v;
while m >= 10.0 do begin m := m / 10.0; e := e + 1; end;
while m < 1.0 do begin m := m * 10.0; e := e - 1; end;
scaled := Round(m * 1e16);
```

One rounding per iteration — **a hundred of them for 1e100** — and the
accumulated error reaches the 16th significant digit, which is inside the 17
digits being printed. The file's own comment already notes this branch has "its
OWN normalise loops (a third copy, beside FloatToStr's and FloatToExpStr's)".

## The fix already exists, in the other half of the tree

`lib/rtl/sysutils.pas` has an exact decimal expansion —
`ExDecDigits` / `ExDecRound`, base-10^9 limbs, half-to-even on a genuine
remainder — and `FloatToStr` built on it is **correct for every row above**.
Track B moved `Format`'s `%e` and `%g` onto it on 2026-08-04 (see
compat-pascal-format-g-and-e-specifiers) and they now match FPC exactly,
including subnormals (`1e-320`) and the `1e200` exponent.

So this is a port, not a research problem. The awkward part is only that
`compiler/builtin/**` cannot `uses sysutils` — it *is* the runtime — so the
expansion has to be duplicated there or factored into an include both can
share. Factoring it is the better answer given the file already admits to
carrying three copies of the naive loop.

## Why Track B filed rather than fixed it

`compiler/builtin/**` is Track A ground (it is named as such in the Track O
description). The RTL-side half is done and gated; this half needs A.

## Verification recipe

```pascal
var d: Double;              { a VARIABLE -- a literal would be Extended in FPC }
begin d := 1e200; writeln(d); end.
```
Compare against FPC **and** CPython (`f'{1e200:.16e}'`); require both to agree
before trusting either. `test/lib_format_ge.pas` has the same values as
Format-level expectations and can be lifted directly once this is fixed.

## Resolution (2026-08-05)

The ticket said "this is a port, not a research problem" and that is how it
went — but the scope was **four copies, not one**. Grepping the writers found
the same normalise-by-repeated-division loop in:

| copy | used by |
| --- | --- |
| `EmitWriteFloatSci` (`symtab.inc`, ~200 lines of hand-written x86-64) | writeln on x86-64 |
| `EmitWriteFloatSciA64` (~180 lines of hand-written aarch64) | writeln on aarch64 |
| `PXXWriteFloatSci` (`builtinheap.pas`) | writeln on i386/arm32/riscv32 |
| the `width < 0` branch (`builtin.pas`) | `Str(F, S)` |

All four were wrong the same way, which is why every target agreed on the wrong
answer and why `Str` and `writeln` could still disagree with each OTHER
(`...006` vs `...007` for 1e100). The x86-64 emitter's own header already
conceded "the last 1-2 digits may differ from a correctly-rounded bignum
formatter", and `FloatToExpStr`'s recorded a DEAD END warning that scaling the
double first cannot be made to work and that "any real fix has to round the
DIGITS from an integer representation". Both were right.

**`PxxSciDigits17` in `builtinheap.pas`** — the exact decimal expansion, as
`sysutils.ExDecDigits`/`ExDecRound` does it (base-10^9 limbs, half-to-even on a
genuine remainder), with one deliberate difference: **it builds no string**.
That layer is the allocator and has no `IntToStr`/AnsiString concat to lean on,
and the caller only ever wants 17 significant digits — which max out at
99999999999999999 < 9.2e18, so the answer fits an `Int64` and the whole routine
stays integer arithmetic. That is what makes it usable from the write path
without touching the heap.

**Four copies collapsed to one.** The two native emitters are now thin shims
that spill the double and call `PXXWriteFloatSci`; `Str` calls `PxxSciDigits17`
directly (builtin-unit symbols resolve globally, so `builtin.pas` needs no
`uses` — verified). ~380 lines of hand-written assembly deleted.

### Verified

Every row of the ticket's table now matches FPC **and** CPython exactly,
including the `1e200` exponent. Beyond the table: zero, negative zero, `1.0`,
negatives, `0.1`, max double, and the smallest subnormal `5e-324` — which
exercises the 767-digit worst case — all identical to FPC. Non-finite guards
still hold (` Inf`/`-Inf`/` Nan`, no hang). Identical on x86-64, i386, arm32,
aarch64 and riscv32. `lib_floattostr`, `lib_format_ge` and
`test_nilpy_float_repr.npy` all still pass, so the sysutils and pylib copies
still agree with this one.

### Cost, measured and not hidden

200 000 `writeln` of a Double: **5.34s before, 7.21s after (+35%)**. The exact
expansion is genuinely more work than a scaling loop. Most of BOTH figures is
the per-character `write(ch)` in the writer (23 syscall-ish writes per number),
which is why the absolute per-call cost only moves ~27µs -> ~36µs; batching that
into one write would dwarf this difference in either direction, but that is an
optimisation ticket, not this fix. Halving the divisions in the limb multiply
(one `div` plus a multiply instead of `div` + `mod`) recovered ~0.2s of it.

Correct float output is worth 9µs on a path nothing runs in a hot loop, and the
alternative is printing a number that is wrong in the 16th digit and sometimes
in the exponent.

**Gate:** `testmgr --tier quick` 15/15; `selfhost_fixedpoint.sh` converges in 2
rounds from `pinned` and agrees with `compiler/pascal26`.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
