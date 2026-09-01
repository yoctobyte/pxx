---
type: bug
track: A
prio: 7
summary: an interface function result leaked every reference unless stored in a variable — two independent defects, the sret temp had no owner and a bare loop body never flushed
owner: frankB
---

## What

`TakeI(MkIntf(k))` leaked one object per call, `frees=0`. So did the by-value
parameter and a method call straight on the result. Only storing the result in a
variable was clean.

FPC's heaptrc says **`0 unfreed memory blocks`** for the same program, so this is
a divergence from the oracle, not a policy choice.

## Two independent defects — neither fix works alone

Measured by building each on its own; each alone still reads `frees=0`.

**1. The sret temp had no owner.** An interface-returning call lands its result
in a hidden caller-side temp. The argument path then RETAINS out of that temp
into its own and releases *that* one at end of statement, so the call site
reconciled and the factory's own reference did not.

**2. A bare loop body never flushed.** `IRFlushPostCallIntf` ran at `AN_SEQ`
(per statement) and per `if` arm, and nowhere else. A loop is ONE statement, so a
body that is not a `BEGIN`/`END` block never reached `AN_SEQ`: every by-value
interface *and managed-record* argument temp the body created was finalized
ONCE, after the loop, on the slot's LAST occupant. Every earlier occupant was
overwritten with no release at all.

Defect 2 is the same mechanism `bug-a-managed-temps-for-an-untaken-branch-are-
still-init-and-finalized` fixed for `if` arms, one statement kind over — and the
comment at that site already spells out why an enclosing-statement boundary is
the wrong one. Loops were not covered.

**The control that separated them.** With a printing destructor,
`for k := 1 to 3 do TakeI(MkIntf(k))` destroyed only `N=3` while FPC destroyed
all three; wrapping the IDENTICAL body in `begin ... end` made pxx destroy all
three. Same temp, same call, different flush boundary.

## Measured

| arm | before | after | allocs |
| --- | --- | --- | --- |
| `TakeI(MkIntf(k))` const param | 921, frees=0 | 1, frees=920 | 921 |
| `TakeIv(MkIntf(k))` value param | 921, frees=0 | 1, frees=920 | 921 |
| `MkIntf(k).Id` method on result | 921, frees=0 | 1, frees=920 | 921 |
| `g := MkIntf(k)` — **control** | 921/919 | 921/919 | 921 |
| `g := MkIntf(k); TakeI(g)` — **control** | 921/919 | 921/919 | 921 |

`test/test_interface_result_temp_leaks.pas`: **2503 → 3** against a bound of 50,
on `a4c67a5e6cc8` vs the fixed binary, `allocs` 4274 either way. Rejected by the
pre-fix binary (rc=1). Identical on x86-64/i386/aarch64/arm32/riscv32, and the
pre-fix binary prints the same `sink=1003000` on all five while leaking.

All three loop kinds are in the test because the flush had to be added to each
separately, and a fix present in two of three is the shape that stays broken. The
managed-record by-value arm is there because it rides the same queue: a wrong
move for it is a double finalize rather than a leak, so the test also runs under
`-dPXX_HEAP_DEBUG`, clean, and matches FPC's output.

pxx releases the temp at the end of the statement containing the call; FPC defers
it to the next statement. Both destroy the same objects the same number of times,
which is what the destructor-print control checks.

## Log

- 2026-09-01 — found by sweeping managed kinds other than strings through the
  ownership seams; fixed and closed in the same session, commit 1308ef1f8.
