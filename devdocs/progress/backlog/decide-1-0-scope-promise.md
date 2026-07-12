---
prio: 55
---

# DECIDE: what does 1.0 actually promise?

- **Type:** decide (user call — nobody else can make this one)
- **Track:** A (core owns the gate that 1.0 certifies)
- **Status:** backlog — opened 2026-07-12.
- **Owner:** — (user)
- **Unblocks:** [[feature-promo-launch-plan]] (the launch is gated on 1.0 existing)

## The trap this ticket exists to avoid
"So much on the to-do" is a feeling that **never goes away** — the backlog of a compiler grows
forever, because every language you accept and every target you add generates more of it. If
1.0 means *"the TODO list is short"*, **1.0 never ships.** That is the default failure mode and
it is worth naming.

## The reframe
**1.0 is a promise, not an absence of TODO.** It is a *scoped guarantee* about what works and
what will keep working. Everything outside the scope is 1.1+, and saying so out loud is not a
weakness — it is what a version number MEANS to everyone else.

Concretely, 1.0 should answer:
1. **Which frontends** are in scope, and at what surface? (Pascal, surely. C — at what level:
   "compiles the corpus we ship" vs "C99"? Rust/Zig are explicitly experimental → out.)
2. **Which targets** are supported vs. best-effort? (x86-64 native surely; i386/aarch64/arm32
   proven by self-host; riscv32/xtensa emit-only bare-metal.) Say which are *promised*.
3. **What is the stability promise?** The important one. Suggested: *"code that compiles under
   1.0 keeps compiling through 1.x"* — a source-compatibility promise, not a feature-count one.
4. **What is explicitly NOT promised** at 1.0 — optimizer output stability, ABI stability for
   the IR, the experimental frontends, GUI. Naming the exclusions is what makes the inclusions
   credible.

## Why it gates the launch
The launch spends a one-shot resource (see [[feature-promo-launch-plan]]). It needs a working
install and a claim that survives an hour of hostile clicking. Both require knowing what we are
claiming. So: this decision first, then the plan, then the launch.

## Log
- 2026-07-12 — opened. User wants a real 1.0 and knows we are far from it; the point of this
  ticket is to ensure "far from it" is measured against a *decided scope*, not an infinite list.
