---
track: B
prio: 20
type: bug
blocked-by: []
summary: "Floor(1e30) returns 0 and Floor64(1e30) returns Int64 MIN, silently. FPC raises EInvalidOp. A silent wrong VALUE where the reference implementation refuses — found while documenting the C-vs-Pascal math split, 2026-08-14."
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
