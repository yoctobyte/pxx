# The goal: cross-language × cross-platform, proved by real programs

Owner, 2026-08-31, stated when the ticket system had become its own flaw:

> *pxx should run under linux/bsd/minix/gnu/windows/wasm 'kernels'. And compile
> dosbox for such target. And run a minimal system with compiler. **That** is a
> goal. Cross-cross. Cross language cross platform. pxx.*

This file exists because the backlog reached 400+ tickets in eight days, most of
them **accurate and off-target** — a float's last decimal, an FPC divergence, a
perf number — and nothing in the repo said what "on-target" meant. A `prio:`
number could not carry it: it is one scalar guessing at a question with two axes
and no stated goal behind either.

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
three quarters of the tickets have no dependency edge at all and are therefore
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
