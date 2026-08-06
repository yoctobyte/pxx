# Handoff — float exactness, Track A + B (2026-08-06)

**A self-prompt for a fresh context, not a spec.** `CLAUDE.md` remains the
authority on gating. Predecessor: `2026-08-05-track-ap-bughunt-night3.md`.

Tree state at handoff: clean, everything pushed, **pinned v244**,
`gate.sh quick` GREEN (self-host fixedpoint + quick tier), `working/` empty,
no lane locked. Track T's full matrix went GREEN at `cc4116ba900d` — the first
fully green full matrix in the tstate record.

---

## The prompt

> Two float-formatting bugs, one in each lane, found together and worth doing
> together — they are the same *kind* of bug and both have their correct
> implementation already sitting unused in the same file.
>
> **Track A** — `write(v:w:d)` prints digits that are not the value's digits
> once `|v| > 1e22`.
> **Track B** — `Format('%.Nf')` is wrong from `|v| ~ 9e13` and prints outright
> garbage from `~9.2e16`.
>
> Neither is a regression; both are long-standing. Take them as one piece of
> work — but land them as **separate commits in their own lanes**, with their
> own gates.
>
> Suggested order: **B first.** It is nine orders of magnitude more reachable,
> it is the one a user hits with money-in-cents or a nanosecond timestamp, and
> `lib/rtl` is the smaller blast radius. Do not let that ordering become a
> reason to skip A.

---

## Track B — `bug-b-format-fixed-overflows-int64-and-loses-digits` (prio 65)

`lib/rtl/sysutils.pas`, `FmtFixed`, around line 2044:

```pascal
scaled := Trunc(v * k + 0.5);   { scaled: Int64; k = 10^prec }
ip := scaled div k;
fracStr := IntToStr(scaled mod k);
```

Scales the whole value into an **Int64**. Two regimes (figures for `prec = 2`):

| threshold | value | result |
| --- | --- | --- |
| `v*k` > 2^53 | v ≈ **9.0e13** | last digit(s) silently wrong |
| `v*k` > 2^63 | v ≈ **9.2e16** | `Trunc` wraps to Int64.Min → `-92233720368547758.-8` |

Measured:

    Format('%.2f',[123456789012345.67])   pxx ...45.68            FPC ...45.67
    Format('%.2f',[1e17])                 pxx -92233720368547758.-8
    Format('%.2f',[1e30])                 pxx -92233720368547758.-8   (same constant)

Note the minus sign **inside the fraction** on positive input.

**The fix is already in the file.** `sysutils` has exact base-10^9 decimal
machinery — `ExDecDigits` / `ExDecRound` — used by the `%g` and `%e` paths.
`FmtFixed` predates it and never adopted it. Routing through it removes both
thresholds at once, because the expansion is exact integer arithmetic instead of
a scaled double.

**Gate:** Track B — build with `$(PXX_STABLE)`, never rebuild the compiler;
`make lib-test`. **Run the cross sweep** (`tools/lib_cross_sweep.sh`): a past
session shipped an i386 regression from an RTL change because `gate.sh lib` is
x86-64 only — see the `crtl-changes-need-a-cross-check` lesson.

---

## Track A — `bug-a-write-fixed-emits-false-digits-past-1e22` (prio 60)

`compiler/builtin/builtinheap.pas`, `PXXWriteFloatFixed`. Generates the integer
part in `Double` arithmetic:

```pascal
var x, pw, v, ip, rem, dv, r, two52, ipc: Double;
while ipc >= 10 do begin ipc := ipc / 10; ndig := ndig + 1; end;
d  := Trunc(rem / dv);
dv := dv / 10;
```

Past 2^53 a double cannot represent consecutive integers, so dividing down by
powers of ten cannot recover decimal digits. Measured:

    1e15..1e22  correct  (1e22 is the largest exactly-representable power of ten)
    1e23   pxx 100000000000000000000000          exact 99999999999999991611392
    1e25   pxx 10000000000000002147483648        exact 10000000000000000905969664
    1e30   pxx 1000000000000000140737488355328   exact 1000000000000000019884624838656
    1e300  pxx 99999999999999983567616651958...  exact 10000000000000000525047602552...

The artifacts name the cause: `...2147483648` is 2^31, `...140737488355328` is
2^47 — binary granularity printed as decimal digits. At 1e300 it is wrong from
the **first** significant digit. Some magnitudes (1e23, 1e24, 1e28, 1e29) echo
the decimal literal back instead, which is wrong the other way.

**The fix is already in the file.** `PxxSciDigits17` in the same unit expands a
double **exactly** with base-10^9 integer limbs (`PXX_SCI_LIMBS`,
`PXX_SCI_BASE`) — a double is `mantissa * 2^exp`, so an exact decimal expansion
always exists and needs only integer arithmetic. The scientific path uses it and
is correct; the fixed path does not.

**Gate:** the per-fix loop — `make compiler/pascal26` (~12s, IS the fixedpoint),
run the repro, `tools/gate.sh quick`, commit, push. Do **not** widen it.
`compiler/builtin/**` is Track A's ground (CLAUDE.md names it alongside
`ir_codegen.inc`), so this is A even though it looks like library code.

---

## Use an oracle. This is the whole lesson from how these were found.

`decimal.Decimal(float(x))` gives the exact value of a double in one line:

```
python3 -c "from decimal import Decimal; print(Decimal(float('1e30')))"
1000000000000000019884624838656
```

I found these only because the user asked whether we render floats *better*
than FPC. I had written into two tickets that pxx prints "the true value" —
having compared **two implementations against each other** and never either
against the exact value. Both were wrong. FPC is not an oracle for exactness;
it computes in Extended and prints its own approximation.

So: compare against `Decimal`, and use FPC only for the *policy* question
(what should be printed), never for the *correctness* question (what the digits
are).

---

## Do NOT unify the three copies

The exact-decimal core now exists in `lib/rtl/sysutils.pas`,
`compiler/builtin/builtinheap.pas` and `compiler/builtin/pylib.pas`, and it is
tempting to treat these two bugs as evidence that the duplication must go.
**User's call 2026-08-06: leave it.** `builtin` has been stable for many weeks,
so the copies are not actually drifting in practice, and
[[decide-builtin-and-library-code-sharing]] stays parked as the hook for next
time. Fix each path in place.

---

## Related, and deliberately not in scope

- `decide-float-fixed-output-exact-or-fpc-17-digit-cap` (prio 45) is **blocked
  on the Track A bug** and should stay blocked until it lands. It asks what to
  print past 2^53 — exact, an FPC-style 17-significant cap, or FPC's
  exponent-form fallback (FPC abandons the fixed form entirely past ~1e300).
  That is a display-policy question and cannot be answered while the digits are
  wrong.
- `compat-pascal-write-fixed-huge-magnitude-differs-from-fpc` (done) carries a
  correction noting its "pxx prints the true value" claim was false. What still
  stands from it: the x86-64 Int64 saturation is gone, the backends agree,
  NaN/Inf are correct, and `1e20:0:2` is byte-identical to FPC.
