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
