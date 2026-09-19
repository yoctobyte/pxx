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
3. **A nice list of working demos.** The measured list, one row per
   `examples/**` program: `devdocs/dev/demo-status.md`.
4. **lekkerzeilen compiles under Nil-Python**, as a demo.
5. **busybox compiles without external libraries**, as a demo.
6. **Beta 0.1.**

### ADDED 2026-09-17, IN HIS OWN WORDS — WHERE THE SIX GET WORKED RIGHT NOW

The six above are unchanged. This says which of them is being worked and on what
hardware, because he set it out loud and a direction that lives only in a peer
message is a direction the next context boundary loses. **Heard firsthand by the
seat that wrote this**, which is the only way a line may enter this section:

> *"get back to our original goals. so, for PC platforms — this is demo
> applications like lekkerzeilen. which proven to be a very nice all-round test
> subject. but the other part would be to focus on ESP32 once more."*

So goal 3 (working demos) has **two halves and they are different hardware**:
lekkerzeilen carries the PC half and is explicitly valued as *an all-round test
subject* rather than as one demo among many; **ESP32 is back on, as the other
half.** That is a return to origin, not a new direction — pxx began as an
ESP32 Python-like language.

**His framing for why ESP matters now**, prompted by Adafruit shipping
CircuitPython "Turbo" the same week (host-compiled `@native`/`@viper` functions
delivered to the board as `.mpy`, a 2-3 KB loader and **no on-board compiler**,
`-march` covering `xtensa`, `xtensawin` and `rv32imc`):

> *"before we had to recompile micropython for builtins, which still left it up
> to the interpreter, this is a slightly other class of optimization. there's
> still no 'we build a static python application for your ESP'. where we still
> shine."*

**That is the claim to aim at, and it is NOT TRUE YET.** Measured 2026-09-17: a
Mandelbrot `.npy` that runs correctly on the host is refused for `esp32s3` AND
`esp32c6` by one wall — *"a heap arena needs mmap, which bare metal has not"*
(`bug-a-nilpy-on-cross-targets-four-remaining-walls`, re-ranked to 85, held by
franks-ee). One wall, both ESP architectures. **Until it falls: "pxx runs on
ESP32" is TRUE (Pascal reaches xtensa) and "pxx compiles Python to ESP32" is
FALSE, and neither goes into public copy in the other's place.**

**SUPERSEDED IN A NAMED SCOPE, 2026-09-19 — "pxx compiles Python to ESP32" IS
NOW TRUE FOR THE ESP32-C3 AND THE ESP32-S3 UNDER ESP-IDF, UNDER QEMU. NO REAL
CHIP HAS RUN IT.** `examples/esp32/nilpy-c3` and `examples/esp32/nilpy-s3`
build one NilPy program (a class, a list, a loop, `print`) to a relocatable
object, link it with `idf.py`, boot it in Espressif's qemu, and diff the serial
output against CPython's: byte-identical, one boot, no reboot loop
(`./build.sh qemu-assert`). Say exactly that and no more. **Three things it
does NOT say:** that it runs on silicon (nobody has flashed one); that it runs
on BARE metal (`--esp-profile=bare` is still walled — the paragraphs below are
about that profile and still hold); and that it needs no external tools — the
image is linked by the IDF toolchain, not by pxx. The S3 build also needs
`--xtensa-long-calls` until `feature-a-xtensa-should-not-need-a-flag-to-build-
a-large-image` lands, and both need a compiler newer than pin v412, which
predates both halves: until the next pin, run them with `PXX=compiler/pascal26`.

**THE ARENA WALL FELL THE SAME DAY (`2b2ec3fee`) AND THE CLAIM IS STILL FALSE —
READ BOTH HALVES.** Bare metal has no kernel to ask for an arena, so the arena
does not need obtaining; it needs to BE part of the image, and it is BSS now.
All three of `esp32s3`, `esp32c6` and `esp32c3` move past that refusal. **What
they move ONTO is bigger than what they moved past**: `undefined variable
(PXXVarBinOp)`, which is `--esp-profile=bare` pulling no `builtin` unit at all —
deliberately, and `espassert.pas:24` records that `uses builtin` under that
profile *"really does fail"*, measured, on `PXXVarBinOp` and `PxxSciDigits17`.
NilPy's driver requires `builtin`. So the remaining work is making `builtin`
compile for ESP, which is a different and far larger job than the arena was.

**THE SIZE CLAIM THAT STOOD HERE WAS WRONG, AND IT WAS WRONG IN THE MOST
ORDINARY WAY: IT COMPARED CODE AGAINST SRAM.** Written 2026-09-17, retracted
2026-09-18 after the owner said the one sentence that dissolves it — *"that
should all be code and hence lives in flash memory. a 'hello world' should take
almost no sram at all."* It read that `print("hi")` is ~1.74 MB on i386 and
~3.14 MB on arm32 against 262,144 bytes of C3 SRAM, called that 6.6x to 12x
over, and ranked DCE as the prerequisite. **Every number in it was real and the
comparison was a category error.** Three ways, each checkable:

1. **Those megabytes are `.text`.** The IDF profile keeps `.text` in flash and
   only data+bss need SRAM. The one profile that does load code into IRAM is
   `--esp-profile=bare`, and `defs.inc:2275` says in its own words why: *"qemu's
   esp32c3 machine models it as one RWX region, so the whole image
   (code+data+bss) loads at the IRAM org."* **That is the emulator's map, not a
   chip's**, and the retracted paragraph generalised from it.
2. **DCE cannot move the quantity the question was about.** Measured at
   `a5419adbf`, same program, `--dce` off then on:
   `code=1347352B data=86084B bss=66796B` -> `code=745240B data=86084B
   bss=66796B`. **data and bss are byte-identical.** It is a 44.7% cut of the
   part that lives in flash and a 0% cut of the part that lives in SRAM.
3. **The SRAM-resident figure is small.** Measured 2026-09-18, same
   `print("hi")`: data+bss is **146,612 B on i386 and on arm32** (85940 +
   60672, identical on both) and 152,880 B on x86-64. Against ~400 KB of usable
   C3 SRAM that is not 6.6x over; it leaves room.

**Cross-checked against a second instrument, because `code=` is page-quantised
(frankuser, 2026-09-18) and a quantised figure would have inflated this one
too.** `readelf -lW` on the i386 binary: the RW LOAD segment is
`FileSiz 0x14fb4 MemSiz 0x23cb8` — **146,616 bytes of memory footprint**, which
is data+bss to within the 4-byte alignment of the bss start, and it is NOT
rounded. (The R E segment IS: `FileSiz 0x185000` against `code=1593196`.) So the
SRAM-resident figure survives the quantisation correction and the code figure is
the one that was approximate all along.

**What the retraction does NOT establish is that it fits.** Three unmeasured
terms sit between 143 KB and a running chip, and none of them is code size:
what IDF itself takes before our first byte, what bare metal adds back (the
64 KB `SocBareArenaSize` arena is BSS by construction), and what it drops (the
hosted 32 KB `SIG_ALTSTACK_SIZE` is in the numbers above and has no bare-metal
counterpart). **Those are rungs of `umbrella-an-esp32-image-is-as-small-as-it-
can-be`, and they are measured, not projected here.** **RUNG 0 IS ANSWERED (2026-09-18, `measure-what-idf-itself-costs-in-sram-on-a-c3`) and it needed no chip: IDF leaves 340,124 bytes of free heap on a C3, ~285,100 with WiFi linked, so 146,612 B of data+bss is 43% / 51% of the budget — it fits in both, with room.** What still needs hardware is the runtime WiFi buffers; qemu's esp32c3 has no radio model and the station example hangs in `esp_wifi_init()`. The escalation
built on the old paragraph — *"is a whole Python program meant to fit inside an
ESP32"* — is in `rejected/` for this reason: **the fork may be real, the number
it rested on was not.**

**The DCE work stands on its own merits and is no longer justified by this
paragraph.** `a5419adbf` wired the NilPy frontend (1889 bodies, 696 live,
1,347,352 -> 745,240 code bytes, self-differential `compared=29 differ=0`).
*"`dce.inc:226` still refuses every non-x86-64 target, so no ESP build has ever
run it"* was true when written and is RETIRED 2026-09-19: wasm32 is the only
architecture the gate turns away now, and both ESP demos have been built and
BOOTED with `--dce` under qemu, output unchanged. Measured the same day, same
program, flashed image: C3 3,326,224 B -> 2,307,648 B (-31%), S3 3,246,288 B ->
1,996,848 B (-38%). Neither reaches the stock 1 MB factory partition, which
needs -66%, so the demos are still built without it. The retracted paragraph's
*"745 KB even WITH DCE"* was measuring a host binary, which is unaffected.

**"One wall, both ESP architectures" is retired as a description, and the
conclusion it supported is UNCHANGED.** That sentence was true of what could be
seen, and clearing the wall is what showed it was never the expensive one —
the first-failure pattern arriving inside a single ticket. **"pxx compiles
Python to ESP32" is still FALSE ON BARE METAL** — no NilPy program runs on ESP
bare metal today (under ESP-IDF, see the scoped TRUE above) — and the arena landing does not move that line into public copy. What it
changes is only the reason: the arena is no longer why.

Linking — a `pxx --link` mode — was discussed the same day and **explicitly
POSTPONED by him**, both his reading and our implementing. It is scoped in
`feature-a-pxx-cannot-link-its-own-objects-...` and is not current work.

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
