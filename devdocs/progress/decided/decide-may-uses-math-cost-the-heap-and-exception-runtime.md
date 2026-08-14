---
track: U
prio: 30
type: decide
blocked-by: []
summary: "Making Floor/Ceil raise EInvalidOp like FPC needs `uses sysutils` in math's implementation — measured, that is the ONLY way to raise anything, since Exception is not visible otherwise. That makes every `uses math` program require the heap + exception runtime: test/test_math.pas stops compiling today. Fork: pay it (and fix the prescan in A), saturate silently, or leave the wrong values. Blocks bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises."
status: decided
---

# May `uses math` cost the heap + exception runtime?

- **Track U** — a design call, escalated rather than guessed.
- Raised by Track B on 2026-08-14 while implementing
  [[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]], which is
  parked in `unfinished/` with the working patch and its FPC diff banked. The
  code half is **done and verified**; this question is the only thing between it
  and landing.

## What is settled, and is not the question

`Floor(1e30)` returns `0` and `Floor64(1e30)` returns `INT64_MIN`. FPC raises
`EInvalidOp`. `0` is the dangerous one — an out-of-range magnitude becomes the
*smallest* answer, so `if Floor(x) > limit` passes.

The ticket recommended option (2), a local range check in the Pascal bodies,
and that works: implemented, and the pxx output then matched FPC 3.2.2 on all
**20 rows** of a table covering ±1e30, ±Inf, NaN, `3e9` (fits Int64 but not
Integer), both Int64 boundaries, and ordinary values — including the subtle row
where **FPC does not raise**: `Floor(3e9) = -1294967296`, because only the
*Int64* conversion is policed and the Int64→Integer narrowing is left to wrap.
Cost measured at +53% on a loop doing nothing but call `Floor64` (0.145s →
0.222s, 20M calls, -O2), which is fine.

## The cost that was NOT anticipated

To `raise` from `math` at all, `math`'s implementation must `uses sysutils`:
`Exception` is not visible otherwise (measured — `raise Exception.Create(…)`
without it is `error: undefined variable (Exception)`). And pulling sysutils in
makes `uses math` require the heap/exception runtime:

```
$ pxx test/test_math.pas /tmp/tm
pascal26:74: error: array of const requires the builtinheap unit
```

`test/test_math.pas` is 27 lines, `uses math`, and touches no string, array or
exception. It compiles today and stops compiling with the fix. The mechanism:
`DetectPascalRuntimeNeeds` (compiler/parser.inc ~32833) decides
`needHeapUnit` by prescanning the **program**, so a need introduced by a unit's
implementation-uses is invisible to it, and sysutils' `Exception.CreateFmt`
(`array of const`) then has no `builtinheap` to compile against.

So the real question is not "should Floor raise" — it is **"is `uses math`
allowed to cost the heap and exception runtime?"** That reaches past floats:
`pxxcio` does `uses math`, so every C program inherits the answer, and Track S's
bare-metal ESP profile is where it costs most.

## The fork

1. **Pay it.** `math` uses sysutils; Floor/Ceil/Floor64/Ceil64 raise like FPC.
   Needs a Track A fix first so a unit's implementation-uses can pull
   `builtinheap` — otherwise heap-free `uses math` programs simply stop
   compiling, which is a worse regression than the bug. **Recommended if and
   only if that A fix is wanted anyway** — the prescan being unable to see a
   unit's own needs looks like a latent defect independent of this ticket.
2. **Saturate** to `High`/`Low` of the return type. No sysutils, no runtime
   cost, nothing stops compiling — and still a silent wrong answer, just a
   less absurd one than `0`. Cheap, and it does not close the bug.
3. **Split the surface**: raise only from a sysutils-side wrapper and leave
   `math` silent. Two spellings of Floor with different contracts, which is the
   double-case shape `devdocs/dev/normalise-dont-special-case.md` warns about.
4. **Leave it**, documented in `devdocs/dev/math-implemented-twice.md`. The
   status quo, and the reason this was filed as a bug rather than a compat item.

**Recommendation: (1), gated on the Track A prescan fix.** FPC parity is the
stated goal for this surface, the runtime cost is measured and small, and the
"heap-free `uses math`" property is worth keeping *deliberately* rather than by
accident — if it is worth keeping, that is itself the answer, and it makes (2)
the honest choice.

## Related, already filed

- [[bug-a-trunc-and-round-of-an-out-of-range-double-return-int64-min-silently]]
  — the builtin half of the same defect, which no RTL change can reach, and
  where each backend gives a *different* wrong answer.
- [[bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes]] — fell out
  of that sweep; unrelated to floats.

## DECIDED 2026-08-14 by the user — our way by default, FPC parity behind a flag

> *"We do it our way unless strict-fpc is set."*

**Default: option 2 — saturate** to `High`/`Low` of the return type. No
sysutils, no exception runtime, nothing stops compiling, and the absurd `0`
goes away. **FPC's raise moves behind an opt-in strict flag.**

This is the house pattern, not a special case: `EnableStrictFpc`'s own docstring
says *"All OPT-IN — the PXX dialect stays deliberately lax by default."*

### Three measurements that decided it

**1. The cost is not small.** This ticket's recommendation said *"the runtime
cost is measured and small"*. Measured 2026-08-14 on the actual program shape:

| program | code | bss | procs |
|---|---|---|---|
| bare | 52 KB | 9.5 KB | 108 |
| `uses math` | 123 KB | 9.5 KB | 295 |
| `uses math, sysutils` | **251 KB** | **42.7 KB** | 637 |

Pulling sysutils roughly **doubles the code and quadruples bss**. On ESP32,
where SRAM is a few hundred KB, that is decisive — and an embedded application
should not abort on a math edge case in the first place.

**2. FPC's raising is a SOFTWARE policy, not hardware.** Same x86-64 machine,
same program:

| | `1/0` | `0/0` | exit |
|---|---|---|---|
| pxx | `Inf` | `Nan` | 0 |
| FPC | — | — | **Runtime error 208** |

IEEE-754 *flags* rather than traps; FPC deliberately **unmasks** FP exceptions.
Intel does not trap by default either — nor do ARM, RISC-V or Xtensa. So "FPC
parity" here means adopting one runtime's choice and paying for it on every
target, including chips where nothing would ever trap.

**3. It would be an island.** pxx already diverges from FPC on the much larger
question of whether FP errors trap at all. Making `Floor` alone raise is
inconsistent with our own established behaviour.

### TWO flags, not one — the costs differ by orders of magnitude

- **`Floor`/`Ceil` raising `EInvalidOp`** — needs sysutils and the exception
  runtime. That is the +127 KB / +33 KB above.
- **FP div-by-zero → runtime error 208** — just unmasks the FPU control word.
  Nearly free, and needs **no exception machinery at all**: a runtime error is
  not an exception, which is Pascal's own behaviour when exceptions are absent.

Lumping them makes the nearly-free one carry the expensive one's baggage.

### Umbrella enrolment is a SEPARATE call

`--strict-fpc` is documented as *"proven to compile the real FPC corpora — fgl,
Synapse, fpjson 203/203"*. Adding a member that drags sysutils into `math`
changes what the umbrella costs for all of them, so enrolment must be decided
with those corpora re-checked, not automatically. **There is precedent for
saying no:** `StrictOverload` is deliberately excluded and kept standalone.

That exclusion may itself become unnecessary — see
[[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]], which
scopes strict flags to external code so our own RTL is never re-judged.

### Consequences

- Unblocks [[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]]:
  saturation is the fix, the raise is the flag.
- Heap-free `uses math` is kept **deliberately** rather than by accident, which
  this ticket correctly identified as the real question.
- `devdocs/dev/math-implemented-twice.md` should record that pxx follows IEEE
  masked semantics by design, so this stops reading as an oversight.

## Log
- 2026-08-14 — decided, commit 87ecef258.
