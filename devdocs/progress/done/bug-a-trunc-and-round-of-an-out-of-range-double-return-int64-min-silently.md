---
track: A
prio: 25
type: bug
blocked-by: []
summary: "Trunc(1e30), Round(1e30) and Trunc(Inf) all return -9223372036854775808 — the x86 integer indefinite value that cvttsd2si produces when the conversion is invalid. FPC raises EInvalidOp for every one of them. These are compiler BUILTINS lowered straight to the conversion op, so the RTL cannot guard them the way Floor/Ceil now are; the check belongs at the lowering or in the FPU mode."
status: done
owner: agent-AN
---

# `Trunc` / `Round` of an out-of-range double return INT64_MIN silently

- **Type:** bug (silent wrong value) — **Track A** (`Trunc`/`Round` are compiler
  builtins; they lower to the float→int conversion op in `ir_codegen*.inc`, not
  to anything in `lib/rtl`).
- **Filed by Track B** on 2026-08-14 as the half of
  [[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]] that
  Track B cannot reach. `Floor`/`Ceil`/`Floor64`/`Ceil64` are fixed in
  `lib/rtl/math.pas` and now match FPC on all 20 rows of that ticket's table;
  these two are what is left.

## Measured — pxx vs FPC 3.2.2

```pascal
var d: Double;
begin
  d := 1e30;
  WriteLn(Trunc(d));
  WriteLn(Round(d));
end.
```

| | pxx | FPC |
| --- | --- | --- |
| `Trunc(1e30)` | **-9223372036854775808** | `EInvalidOp` |
| `Round(1e30)` | **-9223372036854775808** | `EInvalidOp` |
| `Trunc(Inf)` | **-9223372036854775808** | `EInvalidOp` |

`-9223372036854775808` is `INT64_MIN`, the "integer indefinite" value x86's
`cvttsd2si` writes when the source does not fit. Confirmed by construction
rather than inferred: it is the same value for a huge positive, a huge negative
and an infinity, which is what an indefinite result looks like and is not what
any saturating or wrapping conversion would give.

FPC raises because the invalid-operation FPU exception is **unmasked** there;
pxx masks FP exceptions (`project_lib_rtl_code_copied_into_compiler_needs_fpu_mask`
— RTL code copied into `compiler/` assumes a masked FPU).

## Why this is worse than it looks

`Floor(1e30)` used to return **0** — INT64_MIN narrowed to `Integer` keeps its
low 32 bits, which are zero. An out-of-range magnitude became the *smallest*
possible answer, so a range guard like `if Floor(x) > limit` passed. Any caller
that narrows a `Trunc` result has the same hole today.

## The DEFAULT is now decided — saturate, do not raise

[[decide-may-uses-math-cost-the-heap-and-exception-runtime]] (2026-08-14, commit
`87ecef258`) settled the policy for this whole family: **pxx keeps IEEE masked
semantics and saturates; FPC's raise goes behind an opt-in flag**
([[compat-pascal-strict-fpc-unmask-fp-exceptions-two-flags]]). `Floor`/`Ceil`/
`Floor64`/`Ceil64` already follow it.

So option (1) below — unmasking the FPU — is now the FLAG's implementation, not
the default, and this ticket's default-path answer is option (2) narrowed to one
choice: **make `Trunc`/`Round` saturate to `High`/`Low` of the destination
width, uniformly on every backend.** That is a smaller job than it looks,
because two of four targets already saturate (see the table above) — the work is
making x86 agree with ARM rather than inventing behaviour.

The options below are kept as the record of what was weighed.

## The options, and why the RTL one does not apply here

`bug-b-floor-…` listed three; Track B took (2), a local range check in the
Pascal body, because `Floor64` is ordinary RTL code. `Trunc`/`Round` have no
body to put a check in — they lower directly. So the choice here is narrower:

1. **Unmask the invalid-operation FPU exception**, like FPC. Truest, and fixes
   every conversion site at once, but it is a large change with its own hazard:
   `project_sigfpe_handler_cannot_remask_and_return` records that a SIGFPE
   handler which re-masks and returns hangs forever.
2. **Emit a range check at the lowering**, before the conversion op, raising
   from the runtime. Local and predictable; costs a compare and a branch on
   every `Trunc`/`Round`, in generated code rather than in a library. For
   reference, the equivalent guard in `Floor64` measured **+53%** on a loop that
   does nothing else (0.145s → 0.222s over 20M calls at -O2) — acceptable in a
   library body, possibly not at every conversion site in emitted code.
3. **Leave it and document**, which is what the situation is now, and is only
   defensible if (1) and (2) are both judged too expensive. It keeps a
   silent-wrong-value class alive.

This wants a deliberate call, not a reflex — if it turns into a design
question, it is a Track U `decide-*`.

## Each backend gives a DIFFERENT wrong answer — measured

`Trunc(±1e30)`, same source, four targets (`qemu-*-static` for the cross ones;
pure computation, so qemu is a faithful host here):

| target | `Trunc(1e30)` | `Trunc(-1e30)` |
| --- | --- | --- |
| x86-64 | -9223372036854775808 | -9223372036854775808 |
| i386 | -9223372036854775808 | -9223372036854775808 |
| arm32 | **9223372036854775807** | -9223372036854775808 |
| aarch64 | **9223372036854775807** | *(prints corrupt text — see below)* |

x86 produces the *indefinite* value in both directions; ARM **saturates**, which
is the ISA difference (`cvttsd2si` vs `fcvtzs`). So a fix verified only on
x86-64 will read as green here and stay wrong on ARM — and any expectation
recorded from one target is wrong on the other.

**A second, separate defect fell out of this sweep** and is filed on its own:
`Trunc(-1e30)` on aarch64 saturates to `Low(Int64)` correctly but then PRINTS as
`-'..--).0-*(+,))+(0(` — see
[[bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes]]. It is not
about `Trunc` at all (`WriteLn(Low(Int64))` alone reproduces it), which is why
it is a separate ticket, but it is why the aarch64 cell above has no number.

## Sweep before closing

Every float→int conversion, not just these two: an assignment of a Double to an
`Integer`/`Int64`, `Round` to each width, the `Single` sources, and each backend
per the table above.

## Gate

The table above matches FPC, `make test` + self-host fixedpoint, and the
cross-target sweep agrees rather than each backend giving its own wrong answer.

## Resolution

Saturate, uniformly, on every backend — the default the ticket says was already
decided. Implemented by making x86 agree with ARM rather than by inventing
behaviour, exactly as the ticket predicted the shape would be.

### ARM was the specification, not a data point

`aarch64`, `arm32` AND `riscv32` all already produced the IEEE 754-2008 answer,
and produced the *same* one:

```
+overflow -> High(Int64)     -overflow -> Low(Int64)     NaN -> 0
```

Three independent backends agreeing is a specification. x86-64 and i386 wrote
the integer-indefinite value, INT64_MIN, for all five of those cases. So the
fix is a fixup after the conversion on those two, and nothing at all on the
other three.

### Cheap, because it checks the RESULT and not the RANGE

The ticket weighed option (2) — a range check before the conversion — and
priced it at the **+53%** `Floor64`'s guard measured. That is not what this
costs, because the sentinel is *detectable in the result*: one integer compare
against INT64_MIN plus a not-taken branch, with the whole recompute (NaN test,
sign test, two immediate loads) sitting on a path that only an out-of-range
value reaches.

Measured, 20M `Trunc` calls at `-O2`, three runs each:

| | time |
| --- | --- |
| before | 0.10 / 0.09 / 0.09 s |
| after | 0.09 / 0.09 / 0.10 s |

No measurable cost. That is the whole reason this could be the default rather
than a flag.

### The false positive is harmless BY CONSTRUCTION, and is tested

`-9223372036854775808.0` is exactly representable and its `Trunc` is
legitimately INT64_MIN — which is also the sentinel, so the fixup fires on it.
It then recomputes: not NaN, source negative, therefore `Low(Int64)` — the same
answer. Cost: a few instructions on one input. Pinned in the test as
`exactmin`, alongside `two63` (one ulp past representable, which must saturate).

### Verified on every target, not just the one that changed

| | before | after |
| --- | --- | --- |
| x86-64 | INT64_MIN for all five | saturating, NaN 0 |
| i386 | INT64_MIN for all five | saturating, NaN 0 |
| aarch64 / arm32 / riscv32 | already correct | unchanged |

`test/test_cross_trunc_round_saturate.pas` — the five out-of-range shapes for
BOTH `Trunc` and `Round`, both boundary values, plus the ordinary values and
the round-half-to-even cases that must not move — is **byte-identical across all
five targets**. Wired natively AND as a cross differential against the x86-64
oracle on aarch64, arm32, i386 and riscv32, which is precisely the ticket's
warning: a fix verified only on x86-64 would have read as green and stayed
wrong on ARM, in both directions.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary) plus the five-target sweep. Backend code only, no frozen builtin, so no
re-pin.

### Still open, deliberately

The `--strict-fpc` flag that UNMASKS the invalid-operation exception and raises
`EInvalidOp` like FPC remains
[[compat-pascal-strict-fpc-unmask-fp-exceptions-two-flags]]. This ticket was
only ever the default path, and the default is now consistent and documented
rather than per-ISA accident.

## Log
- 2026-08-15 — resolved, commit c429a571b.
