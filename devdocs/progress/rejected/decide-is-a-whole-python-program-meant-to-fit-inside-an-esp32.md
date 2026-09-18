---
track: U
prio: 70
type: decide
blocked-by: []
summary: "MEASURED FORK, not a speculative one: the NilPy runtime for the smallest program that exists (`print('hi')`) is ~1.74 MB on i386 and 745 KB on x86-64 even WITH dead-code elimination running, against roughly 400 KB of usable SRAM on an ESP32-C3. Over at every ceiling — 3.4x on the region we currently map, 2.2x on a C3's usable SRAM, 1.7x on an S3. The question is not how to shrink it; it is whether a whole Python program is meant to run inside the chip's own SRAM at all, or whether Python-on-ESP is a smaller thing than the hosted NilPy runtime. Flash/PSRAM and a reduced runtime profile are different PRODUCTS, not different implementations, which is what makes this the owner's and not ours."
status: rejected
owner: unassigned
---

# Is a whole Python program meant to fit inside an ESP32?

**The one sentence, with no implementation noun in it:**

> *Do we want a whole Python program running inside an ESP32's own 400 KB, or is
> a smaller Python-on-ESP the thing we are building?*

## Why this is a fork and not an engineering question

Everything engineering could answer has been answered and it did not close the
gap. The mechanism, because it is a stated side goal that the reasoning is
available and not hidden:

- The heap-arena wall is **cleared** (`2b2ec3fee`) — bare metal reserves its
  arena in BSS rather than asking a kernel that is not there.
- Dead-code elimination is **wired for NilPy and measured** (`a5419adbf`):
  1889 bodies, 696 live, **code 1,347,352 -> 745,240, a 44.7% cut**, verified
  correct by a self-differential over 29 real `.npy` programs (`differ=0`, and
  zero DCE-only compile failures).
- What remains is not a missing feature. It is arithmetic:

| ceiling | source | NilPy `print('hi')` projected for riscv32 | over by |
| --- | --- | --- | --- |
| 262,144 | the region we map today (`defs.inc`) | ~881 KB | 3.4x |
| ~400 KB | `docs/targets/esp32.md:118`, C3 usable SRAM | ~881 KB | ~2.2x |
| ~512 KB | ESP32-S3 | ~881 KB | ~1.7x |

**Over at every ceiling, on the smallest NilPy program that can be written.** A
real program only grows. The 400 KB row is the one that matters: quoting our own
262,144 map invites "widen the map", and the conclusion survives that.

## What the options actually differ in — and it is what we are trying to BE

1. **Python-on-ESP is the hosted runtime, so the chip must grow.** External
   flash / PSRAM, an XIP or overlay story. This is a different product shape,
   not a smaller image.
2. **Python-on-ESP is a smaller language than hosted NilPy.** A reduced runtime
   profile: no Variant-based marshalling, a restricted builtin set. Cheapest in
   engineering and it means "pxx compiles Python to ESP32" is true of a
   *different Python* than the one that runs on the host.
3. **Python-on-ESP is not a goal; Pascal-on-ESP is.** Pascal already reaches
   xtensa and riscv32 bare metal and FITS. This costs nothing and retires a
   claim.

These are not priced against each other — that would be engineering. They differ
in **what we are claiming to have built**, which is why the answer is not ours.

## What is NOT being asked

Not "how do we shrink the runtime" — DCE is in and measured. Not "which is
cheaper". Not anything requiring knowledge of pxx internals to answer.

## Recommendation

**(2), and it is a weak recommendation held loosely.** The original framing was
*"there's still no 'we build a static python application for your ESP'. where we
still shine"* — and a reduced Python that genuinely runs on a bare chip serves
that better than a full Python that needs added hardware. But this turns on what
the claim is meant to mean in public copy, which is exactly the part we should
not decide.

**Until it is answered:** `the-goal-cross-cross.md` keeps *"pxx compiles Python
to ESP32" is FALSE*, and that line does not move on the strength of the arena or
the DCE work. Both are real and neither makes it true.

## REJECTED 2026-09-18 — THE PREMISE MEASURES CODE AGAINST SRAM

Withdrawn by frank-user, who put this fork in front of the owner and had the
framing corrected by him on the spot. **The ticket is competent and the fork it
describes is real; the number it rests on is the wrong quantity.**

The headline is *"~1.74 MB on i386 and 745 KB on x86-64 ... against roughly
400 KB of usable SRAM on an ESP32-C3."* Those are **code** sizes. The owner's
correction, verbatim:

> *"we know ansistring and dynarrays have some overhead, but that should all be
> code and hence lives in flash memory. a 'hello world' should take almost no
> sram at all."*

He is right, and three measurements since confirm it:

1. **On a real ESP the IDF profile keeps `.text` in flash.** The 400 KB figure is
   SRAM. Only `--esp-profile=bare` puts code in IRAM, and `defs.inc:2275` says
   why in its own words — *"qemu's esp32c3 machine models it as one RWX
   region"*. That is a QEMU shape. Every ratio in this ticket was computed
   against the emulator's memory map, not a chip's.
2. **`--dce` removes zero bytes of RAM.** Measured: code 1,347,352 -> 745,240
   (-44.7%), data 86,084 -> 86,084, bss 66,796 -> 66,796. So "745 KB even WITH
   dead-code elimination running" is a statement about a pass that was never
   operating on the quantity in question — and `dce.inc:226` refuses every
   target but x86-64 anyway, so no ESP build ran it at all.
3. **The actual SRAM floor is small and its composition is known.** An x86-64
   hello world at its 195-byte code floor carries 41,800 B of bss, of which
   32,768 is one constant (`SIG_ALTSTACK_SIZE`, reserved even under
   `--no-signals`).

## The residual question, and who owns it

Not "does Python fit in SRAM" — that was never the measurement. The two real
questions both have an owner now:

- **How much SRAM does IDF itself take?** The owner asked this directly and
  nobody has measured it. It is **rung 0** of
  [[umbrella-an-esp32-image-is-as-small-as-it-can-be]].
- **Can constants be flash-resident at all?** Today, no —
  `grep -c rodata` is 0 in `elfwriter.inc` and `defs.inc`, so there is no
  read-only LOAD segment for them to live in. That is
  [[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]],
  rung 4 of the same umbrella.

Filed under `rejected/` per this repo's four-terminal-folders rule: the report is
wrong (false premise), as distinct from true-but-not-a-defect
(`known-incompat/`) or real-but-deferred (`rainy-day/`). **If the product fork
turns out to be real after rung 0 gives us IDF's number, re-file it stated
against SRAM measured on a chip — it would be a good ticket.**
