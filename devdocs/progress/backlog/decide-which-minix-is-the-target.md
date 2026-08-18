---
track: U
prio: 58
type: decide
blocked-by: []
summary: "MINIX 2 / early 3.1.x (small, plain, ACK-era C) versus MINIX 3.2+ (which imported the NetBSD userland and build system). These are close to different projects for our purposes, and the choice dominates the cost of the whole lighthouse. Recommendation: MINIX 2 / early 3.1.x."
---

# Decide: which MINIX is the target?

Gates [[goal-compile-minix]]. **Must be answered before any work starts**, because
whoever starts will otherwise settle it by accident — and the two options differ
by more than effort.

## The fork

**Option A — MINIX 2 / early 3.1.x.** Small (~15k lines), plain, ACK-era C.
Assembly lives in separate `.s` files, which is the property the entire
"MINIX before Linux" argument rests on. Bounded, with a crisp binary win
condition (it boots or it does not).

- *For:* maximises the one advantage over the Linux dot. Bounded scope. Exercises
  a genuinely new conformance surface (pre-ANSI C, `_PROTOTYPE` macros, K&R-style
  definitions) that none of our modern-C corpora touch.
- *Against:* it is a historical system. Compiling it proves conformance against
  1990s C rather than anything contemporary, and the bug harvest may skew toward
  constructs nobody writes today.

**Option B — MINIX 3.2+.** Imported the **NetBSD userland and build system**
(`build.sh` / `nbmake`).

- *For:* a live system, modern C, and the NetBSD userland is itself an enormous
  and valuable C corpus — arguably a bigger bug harvest than the kernel.
- *Against:* a large tooling surface full of NetBSD-isms. Risks re-importing
  exactly the "depends on way more tooling" problem that the `CC=` decision was
  supposed to sidestep, except here it is the *build system*, not the compiler
  driver. Scope stops being bounded.

## Recommendation

**Option A.** The reason to do MINIX at all is that it is the rung below the
Linux dot — bounded, inline-asm-light, i386-native. Option B trades that away for
corpus size we can pursue separately and more cheaply: **if the NetBSD userland
is the prize, it is its own corpus ticket and does not need to arrive attached to
an OS boot goal.** Keep the lighthouse bounded; harvest NetBSD on its own terms.

## What the answer changes immediately

- Which source tree gets vendored and probed first.
- Whether pre-ANSI C support becomes a real Track C workstream (Option A) or is
  not needed at all (Option B).
- Whether the build story is "`CC=pxx` plus GNU as/ld" (A) or "`CC=pxx` inside
  nbmake" (B), which is a materially larger integration.

## Considerations added 2026-08-18 (user questions) — NONE of this is source-verified

**Flagged explicitly: the notes below are from knowledge, not from reading a MINIX
tree. There is no MINIX checkout on the box. Before this lighthouse is costed,
step one is a PROBE — vendor a tree and measure — not trusting this section.**

### POSIX reach

MINIX 2 was built to be **POSIX.1 (1990) conformant** — that was its headline change
over MINIX 1's V7 Unix compatibility. Classic surface: `open`/`read`/`write`/`fork`/
`exec`/`wait`, signals, termios, directories. **No pthreads**, nothing from
POSIX.1-2008. MINIX 3.2+ retargeted at NetBSD compatibility (POSIX + BSD extensions).

For us POSIX.1 is close to ideal: a **small, closed, well-specified** surface — the
same shape as the C conformance suites we already pass, not an open-ended API.

### Syscalls — the architecturally interesting answer

**The POSIX calls are NOT kernel syscalls.** MINIX is a microkernel: `read()` packs a
message and sends it to the **VFS server**, a userspace process; `fork()` goes to the
process manager. The kernel's own trap surface is tiny — the IPC primitives
(`send`/`receive`/`sendrec`) plus a small set of privileged kernel calls.

**Consequence for pxx: the syscall ABI is MINIX's problem, not ours.** It lives in
MINIX's own libc as a small `_syscall` shim we compile like any other C — no syscall
convention baked into the compiler. And the servers/drivers are, to the compiler,
ordinary C programs, which is what makes the ladder real: PM, VFS and the drivers can
be compiled and exercised long before anything boots.

### Architecture — and this argues AGAINST this ticket's own recommendation

MINIX 1/2 were x86 (8086 → i386), with historical 68k ports. MINIX 3 is i386-centric,
**but 3.3 added an ARMv7 port** (BeagleBone Black, Cortex-A8).

**That port lives in the 3.3 line — i.e. inside Option B, the version this ticket
recommends against.** pxx has a working arm32 backend, so Option B would let one OS
corpus exercise two backends. The recommendation still stands (bounded scope is the
whole reason to prefer MINIX over the Linux dot), but the trade is sharper than the
original framing admitted.

### The strongest argument against the WHOLE goal, recorded honestly

**The bug harvest lands on i386, not on x86-64.** There is no MINIX x86-64 port. Our
default and most-used backend gets essentially no coverage from this campaign.

Partial mitigation: i386 is our **canary backend** — the only one that validates a
symbol's type kind, so it catches untyped-temp bugs the others accept silently
(`project_i386_is_the_canary_for_untyped_temps`). Pointing an OS at the most pedantic
backend is a real stress test. But if the goal is hardening the codegen most users
touch, MINIX does not do that, and that should be weighed against "it is bounded and
it will actually finish."

## A THIRD consideration, and it is the strongest against Option A (2026-08-18)

**Object format.** MINIX 3 uses **ELF**. MINIX 2 used ACK's own a.out-ish format, and
`compiler/elfwriter.inc` is the only object writer we have. So the moment the goal
includes **"pxx RUNS ON MINIX"** rather than only "pxx compiles MINIX", Option A
requires a whole new object writer and Option B does not.

*(Recall, not source-verified — same caveat as the section above.)*

**This reframes the fork.** The user separated two goals this ticket had collapsed:

1. **pxx COMPILES MINIX** — MINIX as a corpus. Option A is better (plain C, assembly in
   separate `.s` files, bounded).
2. **pxx RUNS ON MINIX** — MINIX as a platform. Option B is better (ELF; POSIX.1 with
   processes and no threads maps cleanly onto the existing `--platform=posix` PAL).

The trophy — pxx running on MINIX, compiling MINIX — needs both, and the two halves
disagree about the version. **That disagreement is now the real content of this
decision**, not the original bounded-vs-NetBSD-tooling trade.

## Sequencing note — this may not be the first OS to do

`feature-port-freebsd-native` (**Track A, p55, unblocked, ready now**) is the same
*platform* axis, on a real OS with real users, and `feature-port-multi-os-abstraction`
is the umbrella that a second OS target forces into existence. **A MINIX platform port
would reuse that abstraction rather than invent it**, so FreeBSD plausibly comes first
on cost and usefulness both — leaving MINIX to earn its slot on the *freestanding*
axis (kernel, no libc beneath, sections, link script, boot), which is the one thing
neither a BSD port nor any application corpus teaches.
