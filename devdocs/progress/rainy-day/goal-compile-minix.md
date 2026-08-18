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

## Chunked (user, 2026-08-18) — four separable goals, not one

The user's decomposition, which matters because **chunk 1 delivers the stated value
with none of the other chunks' cost**, and the chunks do not agree on which MINIX.

### Chunk 1 — MINIX as a C CORPUS (Track C). The cheap one, start here.

Compile MINIX sources. Do **not** link, do **not** boot, do **not** run. Pure
C-frontend stress: pre-ANSI `_PROTOTYPE` / K&R definitions, an OS's worth of real
1990s C, and a codebase written for a deliberately simple compiler.

**Needs none of: a.out, PAL, link script, qemu, boot.** It is the same shape as the
zlib / SQLite / tcc / QuickJS corpus rungs that have paid out every time, and it is
the chunk that actually answers *"does this stress our C compiler."* Most
version-tolerant of the four.

### Chunk 2 — a SECOND OBJECT FORMAT (Track A; shared with Track M)

Only needed for MINIX **2** (ACK-era a.out); MINIX 3 is ELF. a.out is genuinely small
and well-specified.

**The shared-cost observation is the useful part:** Windows needs the same thing in a
bigger size — `feature-port-windows-pe` (Track M, **p25**, blocked-by
`feature-port-rtl-over-libc`). What both share is not format code but **the seam**:
`compiler/elfwriter.inc` is currently the only object writer, and nothing abstracts
the target-format axis.

**OPEN — do not file blind:** check whether `feature-port-windows-pe` already covers
that seam before filing a separate Track A ticket for it. If it does not, it is real
shared work serving PE, a.out, and anything after them.

### Chunk 3 — pxx RUNS ON MINIX (platform axis)

PAL over MINIX's POSIX surface, reusing the existing `--platform=posix` /
`lib/rtl/platform/posix` split. POSIX.1 with **processes and no threads** maps cleanly.
**Favours MINIX 3** — ELF, so chunk 2 is not required at all.

Sequencing: `feature-port-freebsd-native` (Track A, **p55, unblocked, ready**) is the
same axis on a real OS, and `feature-port-multi-os-abstraction` is the umbrella a
second OS target forces into existence. A MINIX platform port should **reuse** that,
not invent it.

### Chunk 4 — BOOT a pxx-built MINIX. The trophy; everything else first.

### Why the chunking changes the decision

Chunks 1 and 2 want **MINIX 2** (plain C, separate `.s` files, bounded). Chunk 3 wants
**MINIX 3** (ELF, no new object writer). So `decide-which-minix-is-the-target` should
be answered **per chunk**, or chunk 1 should be started version-agnostically and the
version decided when chunk 2 or 3 is actually reached.

## Rejected sibling — GNU Hurd (considered and declined, 2026-08-18)

Raised as a candidate and declined the same evening: **Hurd has MINIX's irrelevance AND
Linux's GNU-extension burden.** It is a GNU project built by GCC, so it leans on the
GNU C extensions that MINIX exists to avoid, and its glibc port is entangled enough
that "compile Hurd" pulls in "compile glibc's Hurd port". Debian GNU/Hurd does boot
(i386), so it is not vapour — it simply buys Linux's difficulty at MINIX's audience
size. Recorded so the idea is not re-raised as fresh.
