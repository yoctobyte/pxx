---
track: T
prio: 55
type: feature
status: open
found: 2026-08-30
found-by: claude-T
---

# The differential oracle is blind to layout, and layout is where xtensa dies

## The blind spot, with a live example

`pasmith_run.py` decides everything by comparing a program's **output** across
oracles. That is a strong oracle for one class of defect and structurally
incapable of seeing another: **a program whose values are right and whose
layout is wrong runs perfectly on every target the fuzzer can execute.**

Track S found the case that makes this concrete (relayed 2026-08-30): the ELF
writer has **never aligned the data section on any target**. x86-64 and riscv32
tolerate unaligned word loads, so they compute the right answers and say
nothing. Xtensa faults. 41 xtensa programs are currently green only because an
unrelated performance commit's page padding happens to 4-align the section by
accident — a correctness property held up by a coincidence in an optimisation.

No amount of fuzzing on the current oracle set finds that. Native never faults,
so there is nothing to disagree about. Same structural blindness as the bitfield
`sizeof` finding: the comparison is over the wrong observable.

## Priced at 35, raised to 55 once the evidence landed

Filed the same night at prio 35 on a relayed summary. Four hours later Track A
finished the investigation and every number moved the wrong way:

- The misalignment was **universal**, not a property of the faulting target.
  Every sampled program in BOTH groups was ≡3 (mod 4) — so the 53 that passed
  were never safe, only **untested**. A pass rate was reporting tolerance, not
  correctness.
- The 41 green xtensa programs were green because an unrelated **performance**
  commit's page padding word-aligned the section by accident. A correctness
  property was resting on a coincidence in an optimisation, and had been for
  as long as anyone had been looking at the number.
- Finding it cost a bisect, two throwaway worktrees and most of a night, on the
  single architecture whose hardware is intolerant enough to report it.

One ELF header table would have shown all of it on every target at once, in an
instant. That is the argument for the prio, and it is now a measurement rather
than a prediction. (Track A has since landed an explicit invariant and tested
it the right way — by DELETING the accidental pad and confirming the canary
stays green.)

## What to add

A second oracle **dimension**, not a second oracle: assert properties of the
emitted artifact, alongside the existing assertions about its behaviour.

Cheapest first cut, in rough order of value per line:

1. **Section alignment.** For each emitted section, `sh_addr % sh_addralign == 0`
   and `sh_addralign` is at least the target's natural word size. This is a
   property of one ELF header table — no execution, no QEMU, no oracle to
   disagree with, and it would have caught the live bug above on every target
   at once rather than on the one that faults.
2. **The alignment is INTENDED, not incidental.** The bug above was green by
   accident, so the check must tell "aligned because the writer aligned it"
   from "aligned because something else padded". Assert it with the
   padding-producing passes OFF (`-O0`), where the accident does not apply.

   This requirement is sharper than it reads, and it is the half most likely to
   be dropped as fussiness. **The thing that hid the bug was a perf pass.** A
   check that runs only where optimisation is on measures a tree in which the
   concealer is present, and would have returned clean for months while the
   defect sat there. Generally: *check a property where the thing that would
   hide it is absent* — otherwise you are measuring the concealer's reach, not
   the property.
3. Later, if it earns it: section overlap, `p_align` on the program headers,
   entry point alignment.

## Why it belongs to T and not to A

The **bug** is Track A's — the ELF writer is core. This ticket is the **tool**:
a dimension in the fuzz oracle that makes that class of defect findable at all.
T owns the tool, never the bug. Anything it finds gets filed into the owning
lane like any other tstate red.

## Scope note

Do NOT reach for "run everything under xtensa" as the answer. That makes the
one target that faults the oracle for a property all targets share, which is
slow, needs hardware or an emulator that does not currently run in the fuzz
loop, and still only catches alignment bugs that happen to be exercised by a
generated program. Checking the header is exact, instant, and total.

Gate: `tools/pasmith_*_devtest.py` green, pure guards, plus one deliberate
negative control — an artifact with a knowingly misaligned section must turn the
check red.
