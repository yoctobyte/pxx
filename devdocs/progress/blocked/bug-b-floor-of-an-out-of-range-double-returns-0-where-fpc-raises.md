---
track: B
prio: 20
type: bug
blocked-by: [decide-may-uses-math-cost-the-heap-and-exception-runtime]
summary: "Floor(1e30) returns 0 and Floor64(1e30) returns Int64 MIN, silently. FPC raises EInvalidOp. A silent wrong VALUE where the reference implementation refuses — found while documenting the C-vs-Pascal math split, 2026-08-14."
status: working
owner: track-b-bughunt
---

# `Floor` of an out-of-range double returns 0 instead of raising

Found while writing `devdocs/dev/math-implemented-twice.md` — not from a report.

## Measured

```pascal
program big; uses math;
begin
  WriteLn('Floor(1e30)   = ', Floor(1e30));
  WriteLn('Floor64(1e30) = ', Floor64(1e30));
end.
```

| | `Floor(1e30)` | `Floor64(1e30)` |
| --- | --- | --- |
| pxx | **`0`** | **`-9223372036854775808`** |
| FPC | `EInvalidOp: Invalid floating point operation` | — |

Both pxx answers are silent garbage. `0` is the worse of the two, because it is
a plausible number that arithmetic will happily carry: an out-of-range magnitude
becomes the *smallest* possible answer, so a guard like `if Floor(x) > limit`
passes.

For contrast, the C side is simply correct — `floor` returns a `double`, so
there is no range to leave:

```
C (pxx):  floor(1e30) = 1000000000000000019884624838656
```

That contrast is the point: this is not a shared-math bug, it is specific to the
Pascal surface's `Floor: Integer` signature, which is FPC-faithful and therefore
has a range FPC actively polices.

## Not a compat-tag item — promoted

The repo's compat tag is for parity work; **a finding that means silent wrong
behaviour is promoted to a normal `bug-` ticket in the owning lane.** This is
that: the values are wrong, not merely un-FPC-like.

## Likely mechanism — VERIFY, do not assume

FPC raises because the invalid-operation FPU exception is UNMASKED there. pxx
masks FPU exceptions (see `project_lib_rtl_code_copied_into_compiler_needs_fpu_mask`
— RTL code copied into `compiler/` assumes a masked FPU), so the out-of-range
`cvttsd2si` yields the integer indefinite value (`INT64_MIN`) instead of
trapping, and `Floor`'s narrowing to `Integer` then truncates that to `0`.

That explains both rows, which is why it is worth stating — but it is a
hypothesis from the shape, not a measurement. Probe it before fixing; this repo
has a documented history of plausible wrong root causes.

## Choose the answer deliberately

Three defensible behaviours, and this needs a call rather than a reflex:

1. **Raise, like FPC.** Truest to the reference, but unmasking FP exceptions
   globally is a large change with its own hazard —
   `project_sigfpe_handler_cannot_remask_and_return` records that a SIGFPE
   handler which re-masks and returns hangs forever.
2. **Range-check in `Floor`/`Ceil`/`Floor64`/`Ceil64` and raise from Pascal.**
   Local, cheap, no FPU-mode change; costs a compare per call.
3. **Saturate** to `High/Low(Integer)`. Cheapest, still not FPC, still silent.

(2) looks right and is the recommendation, but the choice belongs in the ticket
rather than in whoever picks it up first.

## Sweep before closing

`Trunc`, `Round`, `Ceil`, `Ceil64`, `Floor64`, and the `Int64` variants, at
±1e30, ±Inf and NaN — same signature family, same conversion, so the same hole.
Check each against FPC.

## Gate

The table above matches FPC (or the chosen alternative is documented in
`math-implemented-twice.md`), the sweep agrees, `make lib-test` green.


## Priority — float handling is parked low (user, 2026-08-14)

> *"bugs related to float handling have low prio atm. they are mechanical, and do
> not impact the compiler, and are for track B"*

Re-rated from 55 to 20 on that call. The defect itself is unchanged and the write-up
below stands — this is a ranking decision, not a downgrade of the finding. Same
judgement the user already applied to float PERFORMANCE work in
`feature-opt-float-register-temporaries` (prio 20, 2026-07-19), now extended from
speed to accuracy.

## 2026-08-14 — mechanism CONFIRMED, fix written and verified, PARKED on a design call

### The hypothesis was right — measured, not assumed

The ticket asked for the mechanism to be probed rather than believed. It holds:

```
Trunc(1e30)   = -9223372036854775808     Round(1e30) = -9223372036854775808
Floor64(1e30) = -9223372036854775808     Floor(1e30) = 0
```

`-9223372036854775808` is `INT64_MIN`, the x86 *integer indefinite* value
`cvttsd2si` writes when the source does not fit — the same value for a huge
positive, a huge negative and an infinity, which is what an indefinite result
looks like and is not what saturation or wrapping would give. `Floor`'s
narrowing to `Integer` then keeps its low 32 bits, which are zero. Both rows of
the ticket's table explained, and the FPU-mask reasoning confirmed.

### Option (2) implemented and verified against FPC — 20/20 rows

Guard in `Floor64`/`Ceil64` (`Floor`/`Ceil` and the `Single` overloads inherit
it), spelled as a negated in-range test so NaN — which compares false against
every bound — is caught without a separate test:

```pascal
const TWO_POW_63 = 9223372036854775808.0;
...
  if not ((x >= -TWO_POW_63) and (x < TWO_POW_63)) then RaiseInvalidOp;
```

The bound is the **Int64** range, not the Integer one, and that is not a
shortcut — measured, FPC does **not** raise for `Floor(3e9)`, it returns
`-1294967296`. Only the Int64 conversion is policed; the Int64→Integer
narrowing is left to wrap like an ordinary cast. A guard on the Integer range
would have been "more correct" and wrong.

Verified: ±1e30, ±Inf, NaN, `3e9`, both Int64 boundaries, `Float`/`Float64`
variants, ordinary values, and the `Single` overloads — **identical to FPC
3.2.2 on every row**, where six rows differed before.

Cost, 20M `Floor64` calls at -O2, median of 3:

| | time | |
| --- | --- | --- |
| no check (before) | 0.145s | |
| two open compares (this form) | 0.222s | +53% |
| three compares via `(x<>x) or … or …` | 0.276s | +90% |
| one call to a helper doing the compares | 0.33s | +130% |

### Why it is not landed

**To `raise` from `math` at all, `math` must `uses sysutils`** — `Exception` is
not visible otherwise (`error: undefined variable (Exception)`). That makes
`uses math` require the heap/exception runtime, and

```
$ pxx test/test_math.pas /tmp/tm
pascal26:74: error: array of const requires the builtinheap unit
```

`test/test_math.pas` is 27 lines, `uses math`, no strings or exceptions. It
compiles today and stops compiling with the fix, so `make lib-test` goes RED —
this is the one thing that turned up in the whole gate. The mechanism:
`DetectPascalRuntimeNeeds` (`compiler/parser.inc` ~32833) prescans the
**program** for `needHeapUnit`, so a need introduced by a unit's
*implementation*-uses is invisible to it and sysutils' `Exception.CreateFmt`
(`array of const`) has no `builtinheap` to compile against.

Putting the `uses` in math's **interface** instead is worse, not better: pxx's
`uses` is transitive ([[bug-pascal-uses-is-transitive]]), and `pxxcio` does
`uses math`, so every sysutils name would enter scope for every C program —
the exact hijack this file's own header comment records as having already
shipped broken once.

So the question stopped being "should Floor raise" and became **"may `uses
math` cost the heap and exception runtime?"**, which reaches into Track S's
bare-metal profile and into every C program. That is a design call, not a
library detail, so it is escalated rather than guessed:
**blocked-by [[decide-may-uses-math-cost-the-heap-and-exception-runtime]]**,
which carries the fork, the measurements and a recommendation.

`lib/rtl/math.pas` is left **unchanged** — master stays green, and the patch is
three lines plus a comment, reproducible from this write-up in minutes once the
call is made. Per `devdocs/dev/root-cause-over-microfix.md`: diagnosis banked,
parked, not consoled with a microfix.

### Split out

- [[bug-a-trunc-and-round-of-an-out-of-range-double-return-int64-min-silently]]
  — `Trunc`/`Round` are compiler builtins, so no RTL change reaches them, and
  **each backend gives a different wrong answer** (x86 indefinite, ARM
  saturates).
- [[bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes]] — found by
  that per-backend sweep and not a float bug at all: on aarch64 only,
  `WriteLn(Low(Int64))` prints `-'..--).0-*(+,))+(0(`, every digit byte being
  `Ord('0') - d`. `IntToStr` and `Str` render it correctly on the same target.
