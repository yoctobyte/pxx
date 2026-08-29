---
track: A
prio: 55
type: feature
blocked-by: []
summary: "EmitLoadVarA64 hardcodes x0 behind residency, dyn-array-handle and sign-extension special cases, so the aarch64 leaf-operand collapse could only be done for the CONST half. The LEAFSYM half needs the right operand in x1 while the left sits in x0; a load-to-x1 twin would duplicate every one of those special cases. Honest fix is a destination-register parameter. Unlocks a further 12-16% of all binops on aarch64."
status: done
owner: frank-optimize
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

---

## DONE 2026-08-29 — both steps, in the order the parked note demanded

Landed as two commits, because the second is only safe after the first.

### Step 1 — one scratch register (`refactor(A): EmitLoadVarA64 has ONE scratch register`)

The parked diagnosis was right about the hazard and **wrong about its size**. It
named "the skGlobal and tySingle arms" as the x1 users. The **by-ref-param deref
is a third** — `ldr x1, [x9]` in both the tySingle and the general arm. Four code
paths across three arms, not two.

That is the third time in two days the same error shape has shown up here: the
bulk-copy ticket's "at least four more places" (really eight), `forwardlint`
naming only the earliest of eight `LowerCase` sites, and now my own note from
yesterday. **The population gets inherited from wherever the first look landed.**
In this case it would not have caused a wrong fix — the collapse had to sweep the
whole routine anyway — but the note would have under-described its own blast
radius to whoever picked it up.

Everything now routes through **x9**. The safety argument is structural rather
than hopeful: the helper *already* destroyed x9 unconditionally on its commonest
path (every local, every parameter), so no caller could have relied on it
surviving; the change makes x9 dead in strictly more cases and x1 dead in
strictly fewer. All 13 call sites checked — the only one holding a live x9 is the
residency spill, which is finished with it before it calls.

Collapsing the scratch collapsed the code: the address computation happens once
per Kind, and the sz/sgn load ladder — **three copies differing only in their
base register** — is now one. 88 lines to 66.

### Step 2 — the destination parameter and its consumer (`perf(O): the aarch64 leaf-sym binop collapse`)

`EmitLoadVarA64Dest(idx, rd)`, rd anything but x9, with `EmitLoadVarA64(idx)` as
the rd = 0 wrapper so the 13 existing call sites are untouched. Kept as a wrapper
rather than a 14th edited call site because a fixed-argument forwarder is not a
duplicated *path* — there is one body, and `normalise-dont-special-case` is about
logic that drifts, which a one-line forwarder cannot.

The binop path then loads a leaf-sym right operand straight into x1.

### The number, and why this one has no gap

3 instructions (12 bytes) saved per leaf-sym binop, predicted from the
`PXXDBG=a.a64binop` census and measured from emitted code:

| program | LEAFSYM | predicted | measured |
| --- | --- | --- | --- |
| loadvar | 323 | 3876 | **3876** |
| mandelbrot | 801 | 9612 | **9612** |
| sieve | 771 | 9252 | **9252** |
| lispdemo | 778 | 9336 | **9336** |
| leafsym | 374 | 4488 | **4488** |

Exact, five for five. Every fire collapsed; none emitted then rewound. Recorded
because the x86-64 float sibling had a 76-fires-vs-37-instructions gap that is
**still only a hypothesis**, and a matching pair here is evidence the counting
method is sound where it was applied — not evidence that the old gap was
imaginary.

-O3 code size: -1.41% to -2.81% across ten programs. -O0 and -O2 byte-identical
everywhere, which is the `OptLevel >= 3` gate proving itself.

### Verification, and the row that stops it being vacuous

| check | result |
| --- | --- |
| self-host fixedpoint | converged 1 round — step 1 `f24d319d76fb`, step 2 `724c6b20181c` |
| aarch64 differential, step 1 | 30 pairs, 0 behaviour differ, **0 size differ** |
| aarch64 differential, step 2 | 30 pairs, 0 behaviour differ, size shrinks at -O3 only |
| non-commutative stress vs x86-64 oracle | identical at -O0/-O2/-O3, under `{$Q+}{$R+}` |
| x86_64 / i386 / arm32 / riscv32 output | byte-identical, all three levels, both steps |
| **step 1: did it change anything at all?** | **332 bytes differ** in the aarch64 binaries |

The last row exists because step 1 is behaviour-preserving *and* size-preserving,
which is also exactly what a no-op edit produces. A vacuous diff has been
published in this repo before; the byte count is the difference between "verified
identical" and "verified nothing".

The **non-commutative stress** is the test that carries step 2. A wrong-way-round
operand pair gives a plausible wrong ANSWER, not a crash, and commutative ops
cannot observe it — an all-commutative test would have passed either way.
`test_a64_leafsym_binops` covers sub/div/mod/shl/shr and all four orderings
permanently; `test_a64_loadvar_arms` covers every width, signedness, global,
by-ref and Single arm of the loader.

### Corpus gaps found while verifying — not fixed, not mine

- **`jsondemo` and `life` do not build for aarch64** — *"aggregate result with
  more than 8 params not supported"*, in `builtin/pylib.pas`. Pre-existing. This
  ticket's census lists jsondemo as an aarch64 data point; that census counted
  target-independent IR shapes so it stands, but the corpus available for
  **behavioural** verification on this target is thinner than it implies. With
  chess (already noted here) that is three of the obvious programs missing.
- **`test_a64_leafsym_binops` does not build for arm32/riscv32** — `{$Q+}` needs
  `PXXOverflow` and builtinheap is not loaded for `softfloat.pas` there.
  Pre-existing, unrelated.
- The differential harness used previously swallowed a failed compile with
  `|| continue`, so a change that broke compilation outright would have appeared
  as a *smaller comparison count*, never as a failure. Hardened to report skips,
  and it earned that immediately: the first negative-control run silently skipped
  3 of 6 pairs.

### Still open, and deliberately not taken

`OTHER` right operands — roughly 6% of binops — still pay the full push/eval/
mov/pop dance. Whether that remainder is worth a ticket should be decided from a
census of what those operands actually are, not from the fact that a number
remains.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
