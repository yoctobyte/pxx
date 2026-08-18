# 🗼 Lighthouse — build and boot MINIX with PXX's C frontend

- **Type:** goal (lighthouse / end-goal — NOT a sprint ticket)
- **Track:** C (C frontend) + A (backend/ELF/codegen where noted)
- **Status:** rainy-day
- **Opened:** 2026-08-18 (user, as a deliberate third horizon dot)
- **Nature:** a fixed point to steer by. Do not "start" this ticket — sub-tickets
  get crafted when we get there.

## The goal

`CC=pxx` builds a MINIX system that **boots to a shell in qemu**. Sibling of
[[goal-compile-fpc-compiler]] (Pascal-side conformance) and
[[goal-compile-linux-tinyconfig]] (C-side conformance).

## Why MINIX before Linux — the argument that makes this worth filing

**The Linux lighthouse's own gap analysis names the GNU inline-asm constraint
engine as THE wall**: constraint letters and modifiers, early-clobber, matching
constraints, `"memory"` as a codegen barrier, operand modifiers, `asm goto`.
Weeks of work, one subsystem, and today `asm` is in the parser's *skip list* —
zero support.

**MINIX was designed to be compiled by ACK, a deliberately simple compiler, and
therefore keeps its assembly in SEPARATE `.s` files rather than inline.** Set
`CC=pxx`, let GNU `as` assemble `mpx386.s` / `klib386.s` untouched, and the single
most expensive item on the OS roadmap largely evaporates. That is the whole case.

Everything else compounds it:

- **Microkernel shape = a free ladder.** The kernel proper is a few thousand
  lines; drivers and servers are ordinary C processes, much closer to the
  userspace corpora we already compile clean. Many small win conditions instead
  of one all-or-nothing boot.
- **i386 is a working, tested pxx backend** (`make test-i386`) and MINIX is
  i386-native — which also deletes `-mcmodel=kernel`, red-zone concerns, and most
  of the x86-64 kernel codegen gates the Linux ticket lists.
- **`--emit-obj` already exists**, producing sane ET_REL objects with sections,
  symbols and relocs (`make test-emit-obj`). The ".o producer inside the standard
  toolchain" decision is already made and partly built.
- **It is BOUNDED.** MINIX 2 is ~15k lines with a crisp binary win condition. The
  Python corpora have no bottom; an OS either boots or it does not. Filed partly
  as an antidote to a campaign whose headline metric cannot show progress.

## THE decision that dominates cost — file it before any work

**Which MINIX?** These are close to different projects:

- **MINIX 2 / early 3.1.x** — small, plain, ACK-era C. The tractable target, and
  the one the argument above is really about.
- **MINIX 3.2+** — imported the **NetBSD userland and build system**
  (`build.sh`/`nbmake`), a large tooling surface with many NetBSD-isms.

**Do not let this be settled by whoever starts.** It is a `decide-*` for Track U.

## Known new ground (not more of the same)

- **Pre-ANSI C.** Old MINIX uses `_PROTOTYPE` macros and K&R-style definitions.
  Every C corpus we have is modern; this is a conformance surface we have never
  exercised. Small, but genuinely new.
- **Reloc breadth** — the ELF writer carries ~4 types; an OS link needs more.
- **Arbitrary named sections** — `elfwriter.inc` hardcodes `.text`/`.data`/`.bss`.
- **Freestanding discipline** — no crtl assumptions, no SSE in kernel code.
- **Pre-console debugging** — nasty, but qemu bring-up for MINIX is far gentler
  than for Linux.

## Relationship to the Linux lighthouse

**MINIX is not a detour from the kernel dot — it is the rung below it.**
Freestanding discipline, no-SSE gating, named sections, reloc breadth, `.o`
producer, boot-in-qemu tooling: every one is a Linux prerequisite, and MINIX
forces them all **minus** the one subsystem that makes Linux expensive. Doing
MINIX first means the kernel stops being a leap.
