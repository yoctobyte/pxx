---
track: A
prio: 55
type: feature
blocked-by: []
summary: "EmitLoadVarA64 hardcodes x0 behind residency, dyn-array-handle and sign-extension special cases, so the aarch64 leaf-operand collapse could only be done for the CONST half. The LEAFSYM half needs the right operand in x1 while the left sits in x0; a load-to-x1 twin would duplicate every one of those special cases. Honest fix is a destination-register parameter. Unlocks a further 12-16% of all binops on aarch64."
status: backlog
owner: ""
---

# `EmitLoadVarA64` needs a destination-register parameter

Track **O** work, Track **A** file ownership (`ir_codegen_aarch64` / the aarch64
backend), so it obeys A's gate.

## Why it exists

`1185b3489` landed the aarch64 leaf-operand collapse for the **CONST** half only.
The census, measured across four programs, is why the remainder is worth a ticket:

| program | binops | CONST | LEAFSYM | collapsible |
| --- | --- | --- | --- | --- |
| `compiler.pas` | 54056 | 80.9% | 12.6% | 93.4% |
| mandelbrot | 4953 | 77.7% | 16.3% | 93.9% |
| chess | 4917 | 77.7% | 16.0% | 93.6% |
| jsondemo | 8016 | 77.9% | 16.0% | 93.9% |

The CONST half alone took mandelbrot at aarch64 `-O3` from 725196 to 683112
bytes — **42084 bytes and 10521 instructions, 5.8%**. The LEAFSYM half is a
further **12-16% of every binop in the program.**

## The blocker, and why it was NOT worked around

The LEAFSYM collapse needs the right operand loaded into **x1** while the left
sits in **x0**. `EmitLoadVarA64` hardcodes **x0**, behind special cases for
residency, dyn-array handles and sign extension.

Writing a load-to-**x1** twin would duplicate every one of those special cases —
and **the duplicate is the arm that stays broken.** That is
`normalise-dont-special-case.md` exactly, and the same shape as
`bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets` filed the same
day: two tables for one concept, one arm corrected, the other left under a
comment describing the fix it did not get.

**The honest fix is a destination-register parameter on `EmitLoadVarA64`**, which
has its own blast radius — every existing call site — and deserves its own ticket
rather than being smuggled into a perf change. Recorded by frank-optimize-b4 at
the time of the decision rather than discovered later.

## Notes for whoever takes it

- Behind `-O3` per the campaign rule (new pass, new target), even though the
  x86-64 sibling has been at `-O1` for a long time. `-O2` is the proven default
  and this is a hot path verifiable only through an emulator.
- **Not timed, deliberately.** qemu does not model the store-to-load forwarding
  that removing two stack ops per binop is mostly about, so a qemu figure would
  understate it by an unknown factor and hardware is unavailable. The code-size
  number above is exact and is what the pass stands on.
- The aarch64 corpus is **thinner than x86-64's**: `chess` does not build for
  aarch64 at all (stackful generator, x86-64 only). Pre-existing and unrelated,
  but it means differential coverage on this target is narrower than it looks.

---

## 2026-08-29, before starting — the approach in this ticket has a hazard, and so does the obvious alternative

Picked up, scoped, **and put back down** after reading `EmitLoadVarA64` properly.
Both findings below are measured from the source, not predicted, and they change
what this ticket should ask for.

### 1. `EmitLoadVarA64` already uses `x1` as a scratch register

Its **skGlobal** arm materialises the global's address with

```
    ldr w1, [pc+8]      <- x1 is the scratch
    b   [pc+8]
    <literal>
    ldr w0, [x1]
```

and the `tySingle` arm does the same. The local/param arms use **x9** instead
(`add x9, x29, x9`). So the helper's scratch register is **inconsistent across
its own arms**, and one of the two choices is exactly the register the binop
path needs as a destination.

> A destination-register parameter therefore **self-clobbers at `rd = 1`** — the
> only value the caller in this ticket actually wants — and it does so **only
> when the operand is a global**, which is the arm least likely to appear in a
> quick test.

That is not a plumbing risk. It is a silent wrong-value risk on one operand
class, on a target verifiable here only through an emulator.

### 2. The no-refactor alternative dies of the same cause

The scheme that needs no change to `EmitLoadVarA64` at all is: evaluate left into
x0, `mov x1, x0`, then `EmitLoadVarA64(right)` into x0, and let a **commutative**
op read the operands in either order — 2 instructions replacing 4, no helper
change, no op-arm change.

It does not work either, for the same reason: **`EmitLoadVarA64` clobbers x1 when
the right operand is a global**, destroying the left value that was just parked
there.

Measured share, in case someone wants the commutative-only subset anyway
(`PXXDBG=a.a64binop`, now split by commutativity):

| program | LEAFSYM_COMM | LEAFSYM_NONCOMM |
| --- | --- | --- |
| `compiler.pas` | 3369 (6.2%) | 3426 (6.3%) |
| mandelbrot | 364 (7.3%) | 442 (8.9%) |
| jsondemo | 619 (7.7%) | 666 (8.3%) |

Roughly an even split, so the commutative-only route is worth about half the
LEAFSYM population at 2 instructions each, versus the full route's whole
population at 3 — and it is **not** the cheap safe option it looks like.

### What this ticket should actually do first

**Make `EmitLoadVarA64`'s scratch usage uniform and stated before adding any
parameter.** Move the skGlobal and tySingle arms onto **x9**, which the
local/param arms already use, so the helper has exactly one scratch register and
can then take any destination except that one. Only after that is the
destination parameter safe.

That first step is a byte-level change to **every global load at every `-O`
level**, so it needs its own verification — the default-`-O` corpus across all
six targets, plus proof that x9 is genuinely free at those points rather than
merely unused-looking. It is not a refactor to fold into the optimisation.

### Why it was parked rather than pushed

CLAUDE.md: *too big for the session, bank the diagnosis in the ticket and park —
never microfix as a consolation.* The consolation move here was visible and
tempting: land the commutative-only subset, book 6-8% of binops, and leave the
global-operand clobber undiscovered inside it. The measurement above is what that
would have cost.
