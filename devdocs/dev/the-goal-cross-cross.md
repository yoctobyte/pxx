# The goal: cross-language × cross-platform, proved by real programs

## THE GOALS, IN THE OWNER'S OWN WORDS, 2026-09-10 — THIS IS THE CURRENT LIST

Asked point blank "so, what were our goals again?" and then answering it himself,
which is the version that counts:

> *the goals are: making a full green pin as release. work application-focused
> instead of bug-fix-focused from now on. have a nice list of working demo's.
> have lekkerzeilen compile under nilpy as demo. have busybox compile as demo
> without external libraries. work toward beta 0.1*

Six, and they are not a re-ranking of the matrix below — they are **what the
matrix is for right now.** Read them as the standing list and everything below
as the reasoning that produced it:

1. **A full green pin, as a release.** Not a pin that grades `reds(N)` — green,
   and shipped as the release. This is the one that makes the others visible to
   anyone outside this fleet.
2. **APPLICATION-FOCUSED, NOT BUG-FIX-FOCUSED, FROM NOW ON.** A standing change
   to how every seat picks work, not a preference. Attempt the target; let the
   failures name the tickets. The backlog is a consequence, never a queue.
3. **A nice list of working demos.**
4. **lekkerzeilen compiles under Nil-Python**, as a demo.
5. **busybox compiles without external libraries**, as a demo.
6. **Beta 0.1.**

**Why this is at the top of this file and not in a ticket.** The owner's
frustration the same evening: *"i'm a bit frustrated about our backlog and never
get to a beta release if we keep hunting such ... that's also why we put all
floating point tickets in its own backlog and never looked back again at them
again. just to discover today we never implemented atan()."* And his diagnosis of
the mechanism, which applies to every seat including the one that wrote this:
*"agentic coding has an ADHD disorder. you dive into anything that grabbed your
attention. and forget about the bigger goal."*

**A session cannot fix that by intending to.** It loses the goal at every context
boundary, so the only thing that works is the goal being written where the next
one trips over it. That is what this section is for.

### "WITHOUT EXTERNAL LIBRARIES" IS GOAL 5 ONLY — NOT GOAL 4 (owner, 2026-09-10)

> *"i do realize lekkerzeilen will need external libraries (at least if we want
> to stay sane). but minimal busybox system (bootable kernel+busybox+pxx) should
> be possible."*

**Do not read goal 5's constraint onto goal 4.** lekkerzeilen binds SDL2 and
OpenGL and is SUPPOSED to — that is a sane dependency on a real graphics stack,
and the `ctypes`/dynamic-loading path that reaches it is the thing that has to
work, not the thing to eliminate. A seat that starts removing SDL2 from
lekkerzeilen in the name of goal 5 has inverted the goal.

The freestanding constraint belongs to **one** target: the minimal system —
**bootable kernel + busybox + pxx compiler, and nothing else.** That is proof #2
from the matrix below, with the vagueness removed, and the owner's word for its
feasibility is *"should be possible"*, not aspirational.

### What goals 4 and 5 are measured against, so "done" is not arguable

- **lekkerzeilen (goal 4).** 20 of 35 modules compiled at last count, and the
  module ratio is NOT the measure: `ctypes` decides whether it runs at all (the
  whole SDL2/GL layer is hand-bound through it), and the `platform/` seam's
  backend is a 39-line stub raising `NotImplementedError`. A demo is the program
  RUNNING, not a census.
- **busybox (goal 5).** "Without external libraries" is **not** what the current
  GREEN means. At 394 applets the separate build is byte-identical to the gcc
  oracle over 938 cases — and its final link is `gcc -o out obj/*.o` against
  **glibc** (`tools/busybox_diff.sh:1429`). pxx emits every object and **cannot
  consume one**, so the link is borrowed. What already meets goal 5 is the
  **unity** build: pxx links it itself, statically, no libc — measured
  2026-09-10, 539008 bytes, `not a dynamic executable`, and it runs. The gate on
  the real shape is
  [[feature-a-pxx-cannot-link-its-own-objects-so-a-freestanding-multi-object-program-needs-gcc]],
  and its first experiment is one run: `ld` over the 521 objects plus crtl, no
  glibc.
  The owner's framing, same evening: *"busybox as gnu-library-free (kernel only)
  pxx test. nothing against gnu. but the goal was: linux kernel + busybox
  executable + pxx compiler as minimal system."*


Owner, 2026-08-31, stated when the ticket system had become its own flaw:

> *pxx should run under linux/bsd/minix/gnu/windows/wasm 'kernels'. And compile
> dosbox for such target. And run a minimal system with compiler. **That** is a
> goal. Cross-cross. Cross language cross platform. pxx.*

This file exists because the open backlog reached **467 tickets** (of 5035 ever
filed, arriving at 70-128 a day — measured 2026-08-31), most of
them **accurate and off-target** — a float's last decimal, an FPC divergence, a
perf number — and nothing in the repo said what "on-target" meant. A `prio:`
number could not carry it: it is one scalar guessing at a question with two axes
and no stated goal behind either.

## CURRENT FOCUS, 2026-09-01: LINUX ONLY — BSD and wasm are demoted

The owner, asked about umbrella pricing: *"we focus on linux only for now. that
means demoting bsd and wasm."* **The goal below is unchanged; the ranking is.**
`umbrella-wasm-is-a-real-platform` and `umbrella-pxx-hosted-beyond-linux` (whose
only children are OpenBSD) are at **25**, as are the BSD leaves that carried
their own higher numbers. Those tickets **stay open and correct** — they simply
must not outrank ordinary Linux work.

**This note is here because the last such ruling was not.** On 2026-08-30 the
owner demoted wasm to 25, recorded it in two ticket bodies, and on 2026-08-31
`8d9a5794b` priced `umbrella-wasm-is-a-real-platform` at 70 from *this
document*, which named wasm in the platform list and said nothing about the
ruling. `effective_prio` then propagated 70 back down and reinstated everything
the demotion had removed. A ruling recorded where the ranker cannot see it was
overturned by a number chosen from a document that did not contain it. **Price
an umbrella from this section first, not from the matrix below.**

NOT demoted, because they are architectures under Linux rather than other
kernels: `umbrella-cross-target-codegen-is-correct` (80 — xtensa, i386, arm32,
riscv32) and `umbrella-managed-memory-is-correct` (75).

**DEMOTED IS NOT FORBIDDEN, and this half is easy to lose.** The owner, same
ruling: *"i didn't say do not do any wasm work at all, if the underlying cause
is identical or similar, might as well fix it on the fly. memory leaks are
indeed a high prio."* So a shared root cause is worked in full — you do not stop
at the Linux arm of a bug whose other arm is wasm, and you do not file the
remainder as a separate low ticket. **A CLASS OF DEFECT IS RANKED BY THE
MECHANISM, NEVER BY THE PLATFORM IT SURFACES ON** — the same rule the F tag
already states for float. What is demoted is *platform-shaped work*: a port, a
runtime host, a capability model for one kernel.

This is why `bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa` keeps
its **75** from `umbrella-managed-memory-is-correct` although its remaining work
is wasm32-only. It is a leak, and leaks rank as leaks.

## The goal is a matrix, and its cells are the only things worth rating

**Languages** (what pxx compiles): Pascal, C, Nil-Python, Rust, Zig.
**Platforms** (where the result runs, and where pxx ITSELF runs): Linux, BSD,
Minix, GNU, Windows, wasm.

"Cross-cross" is the point: not one language on many platforms, and not many
languages on one platform, but the **product**. pxx is the thing that spans both
axes at once — that is the whole proposition, and it is what makes an edge case
in one cell cheap and a missing cell expensive.

## Two proofs, both real programs, both unambiguous

1. **Compile DOSBox for such a target, and run it.** A large real C/C++ codebase.
   It either builds and runs or it does not; there is nothing to argue about and
   no partial credit to award ourselves.
2. **Run a minimal system with the compiler on it.** Self-hosting is already
   proved on Linux/x86-64 every ~12 seconds by `make compiler/pascal26`. The goal
   is that same property on a platform that is not this one — pxx hosted, not
   merely cross-emitted.

A proof is a **program that runs**, not a suite that is green. The suites exist
to stop regressions between proofs; they are not the goal and they never were.

## How this is used — it replaces the priority guess

**A ticket earns its rank by naming the cell it blocks.** Not by someone
estimating importance on a 0-100 scale, which is what produced a backlog where
**91% of open tickets — 425 of 467 — have no dependency edge at all** and are therefore
ranked by a hand-typed guess.

The ranker already implements this and has all along (`tools/progress.py`,
`effective_prio`): *a ticket's effective priority is the max of its own `prio`
and the effective priority of everything it unblocks, transitively — you rate
the goal, the chain follows.* Rate the cells; wire the blockers; the numbers
compute themselves.

So the intake question is **"which cell does this block?"** — answerable, and
often *measurable*, because you can go and try to compile DOSBox and watch what
breaks. It replaces "how important is this?", which nobody can answer
consistently across 400 tickets and which everybody answered differently.

**Don't triage the backlog — attempt the target.** The failures name the tickets
that matter, in the order they matter, and they wire themselves as blockers.
Whatever the attempt never touches was, by construction, not blocking real-world
usage.

## The ceiling this sharpens

`CLAUDE.md`'s compat rule already says we do not chase FPC parity — *"we just
care for correct compiling pascal code, not emulating every behaviour."* This is
the positive form of the same ruling. That rule said what we are **not** doing;
without a stated goal it left "accurate but pointless" indistinguishable from
"accurate and load-bearing", and the backlog is what filled that gap.

**An edge case is not wrong. It is unranked.** It goes to `bugnotes.md` or a
per-lane backlog and waits for a cell to need it. It is not rejected, and filing
one is not a mistake — the mistake was letting it compete with DOSBox.
