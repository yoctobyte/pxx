---
track: U
prio: 45
type: decide
status: backlog
blocked-by: []
found: 2026-09-05
found-by: frankB (measured, on its own retracted closure), frank-coordinator (filed)
summary: "CLAUDE.md's `NOTHING OBSERVABLY DIFFERS IS A CLAIM ABOUT ONE TARGET` names the TARGET ARCHITECTURE and says the default place anyone looks is the 64-bit host. Measured 2026-09-05: the same failure occurred with the variable one level further out -- the BUILD HOST'S INSTALLED PACKAGES. Five regressions were closed GREEN at HEAD on plexus, which has the GTK dev headers, while the failure was on seven, which did not; a host with the headers passes whether or not a bug exists. The author ran the full job rather than the failing step AND measured at HEAD rather than the filed sha -- the two moves that normally rescue you -- and neither could have caught it, because THE DISCRIMINATOR WAS NEVER IN THE TREE. Proposed text below; this is a CLAUDE.md change and therefore the owner's. NOT to be edited in by any agent."
---

# Should the one-target rule name the build host, not only the architecture?

> **This ticket proposes TEXT and does not apply it.** CLAUDE.md is the owner's
> file. Three sessions declined to edit it on a peer's ask on 2026-09-05 and were
> right each time; this seat was the asking peer in two of those.

## What the rule says now

> **"NOTHING OBSERVABLY DIFFERS" IS A CLAIM ABOUT ONE TARGET, AND IT IS HOW REAL
> BUGS GET RANKED AS REFACTORS.** … The dev loop, `gate.sh quick` and the pin all
> run there, so a whole defect class — anything whose width, alignment or pointer
> size is native-only — is **structurally invisible** … **Before ranking one down,
> ask which target the absence was measured on.**

The measured instances behind it are `NativeInt` folding wrongly on i386/arm32/
riscv32, and a method-pointer record hard-sized 16 bytes. **Both authors were
honest and both measured on x86-64.**

## The instance the rule does not cover

**2026-09-05.** Five `test-c-gtk*` regressions, auto-filed from a run on
**seven**, were closed on evidence: each ran its own `Repro` line at HEAD, full
job rather than failing step, **1/1 GREEN**. Retracted within the hour.

> I measured on **plexus**, which has both `/usr/include/gtk-2.0/gtk/gtk.h` and
> `/usr/include/gtk-3.0/gtk/gtk.h`. **A host with the headers passes whether or
> not a bug exists.** "1/1 pass GREEN at HEAD" was true about plexus and silent
> about seven, where the failure happened. — frankB

**The two moves that normally rescue you both ran and neither could work:**
full job rather than failing step, and HEAD rather than the filed sha. **The
discriminator was never in the tree at all.**

**Cost of not having the rule: 18 tickets, four batches** — 3 on 08-21, then 5
each on 08-30, 09-01 and 09-05 — **the same five tests, closed every time, every
closure verified on a host that has the headers.**

*(The gtk instance's own final cause is still being settled — a dist-upgrade sits
between the failing run at 17:54:19Z and a passing run at 19:15:54Z, and the
tickets may name jobs that were never the failing source. **None of that affects
this ticket:** whatever the cause turns out to be, the closure was measured on a
host that could not have observed it.)*

## Proposed addition — the smallest version

Appended to that section, after *"ask which target the absence was measured on"*:

> **And ask which HOST it was measured on.** The same failure occurs one level
> out, where the variable is not the target architecture but **the build host's
> installed packages, toolchain version or absent dev libraries** — and there the
> usual rescues do not work. Measured 2026-09-05: five regressions filed from a
> host with no GTK dev headers were closed GREEN on a host that has them, four
> times across four batches. The author ran the **full job** rather than the
> failing step and measured at **HEAD** rather than the filed sha; **neither
> could have caught it, because the discriminator was never in the tree.**
> **Reproduce a host-filed failure ON THE HOST THAT FILED IT, or say which host
> your green was measured on.**

## The general form, if a broader edit is preferred

frankB's framing, which subsumes both instances:

> **"The discriminator was never in the tree" is the general form.** The
> architecture version is one instance and the build-host version is another,
> **and neither has a gate row or a ticket field.**

That is more useful and more dangerous — a rule stated that generally may not
tell anyone what to *do*. The narrow version above names an action. **Recommend
the narrow one; the general form belongs in the rationale file.**

## Options

- **A — take the narrow addition** as written. Recommended.
- **B — take the general form** ("the discriminator was never in the tree") and
  move both instances to `handbook-rationale.md`.
- **C — neither.** Defensible if the answer is a harness change instead: a job
  that records the host it ran on, so a green from the wrong host is visible
  without anyone remembering a rule. **These are not exclusive**, and C is
  arguably the better durable fix with A as the interim.
