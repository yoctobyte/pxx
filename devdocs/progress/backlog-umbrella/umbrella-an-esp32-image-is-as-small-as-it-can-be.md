---
slug: umbrella-an-esp32-image-is-as-small-as-it-can-be
title: "An ESP32 image is as small as it can be — code and constants in flash, SRAM spent only on what is live"
track: A
prio: 70
type: umbrella
blocked-by: [bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work, bug-a-dce-refuses-every-target-except-x86-64, feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident, bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss, bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok, bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss, bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal, bug-a-the-heap-arena-reserves-256-mib-without-map-noreserve-so-a-small-guest-cannot-run-any-allocating-pxx-program, bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it, feature-a-unreferenced-class-rtti-keeps-every-method-alive, bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]
status: new
created: 2026-09-18
owner: ""
summary: "Owner-set target 2026-09-18: same goal as [[umbrella-a-hosted-program-is-as-small-as-it-can-be]], on ESP, where it is the difference between running and not. An ESP32-C3 has ~400 KB usable SRAM (docs/targets/esp32.md:118) before IDF takes its share — network buffers included, and WE HAVE NEVER MEASURED IDF'S OWN COST, so the budget is not yet a number. Four facts frame it. (1) `--esp-profile=bare` loads code+data+bss into IRAM at $40380000 with a 256 KiB region, because qemu's esp32c3 machine models it as one RWX region (defs.inc:2275) — that is a QEMU shape, not a chip shape; the DEFAULT IDF profile keeps .text in flash. (2) `--dce` is refused on every target but x86-64 at `dce.inc:226`, so no ESP build strips a byte. (3) There is NO .rodata anywhere in the compiler — `grep -c rodata` is 0 in elfwriter.inc and defs.inc — so no constant can be flash-resident by construction. (4) The escape that would shrink an ESP image, `-uPXX_MANAGED_STRING`, SILENTLY EMITS AN EMPTY IMAGE on the bare path and reports `ok:`. That is the urgent one."
---

# The target, in the owner's words

> *"mark as read-only where possible. and strip code and associated data where
> possible."* — 2026-09-17
>
> *"one for PC platforms - and make sure we can emit minimal code. and second
> for ESP, same goal."* — 2026-09-18

This is an **umbrella**. Do not claim it — claim a rung. It shares most of its
blockers with the hosted umbrella deliberately; membership is an edge, and the
ranker takes the max.

**`prio: 70` is a placeholder set by an agent**, not by him.

# Why ESP is a separate umbrella and not a rung of the PC one

Because the two directives pay off in different currencies:

- On a **hosted** target, code is demand-paged from the file. Marking constants
  read-only buys page permissions and cross-process sharing. It does not buy RAM.
- On **ESP**, code and constants have somewhere else to live: flash. Every byte
  moved out of SRAM is a byte of headroom on a chip that has ~400 KB of it.

A fix can therefore be worth ranking here and not there, and vice versa. Keeping
them in one umbrella would rank by the wrong currency.

# What is measured, and what is not

**Measured at HEAD (2026-09-18):**

- `--dce` removes **zero** bytes of data or bss on any target — code
  1,347,352 -> 745,240, data 86,084 -> 86,084, bss 66,796 -> 66,796. Porting DCE
  to xtensa is a FLASH win, not a RAM win. Do not sell it as the RAM answer.
- The data segment of a hosted hello world is 70.7% zeros and 17.4% ASCII, of
  which **6,429 bytes across 197 strings are diagnostic text** — never written,
  and with no read-only segment to put it in.
- The bss floor is 41,800 B, of which **32,768 is the signal alt stack**,
  reserved unconditionally, `--no-signals` included.

**NOT measured, and it is the number this umbrella most needs:**

- **What IDF itself costs in SRAM.** The owner asked directly: *"does this
  include what IDF uses? (because likely network buffers etc do eat up some)."*
  Until someone measures it, "149 KB for nothing" is an unanchored figure and no
  rung here can be said to have made the image fit. **This is rung 0.**

# The rungs

0. **Measure IDF's own SRAM floor**, so the budget is a number. Nothing else
   here is gradeable against "does it fit" until it exists. No ticket yet — file
   one when taking it.
1. **Make size measurable at all.**
   [[bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work]].
2. **Stop the silent-empty-image bug.**
   [[bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok]] —
   urgent, prio 75. The one flag that would shrink an ESP image today produces a
   well-formed ELF that does nothing and says `ok:`.
3. **Give the target a stripping pass at all.**
   [[bug-a-dce-refuses-every-target-except-x86-64]]. xtensa is the primary ESP
   target and riscv32 works; both keep every body today.
4. **Put constants in flash.**
   [[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]].
   This is the owner's first directive and **this is where it pays.**
5. **Stop reserving SRAM for opted-out facilities.**
   [[bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss]] — 32 KB,
   8% of a C3's usable SRAM, for a facility the program said no to.
   [[bug-a-the-heap-arena-reserves-256-mib-without-map-noreserve-so-a-small-guest-cannot-run-any-allocating-pxx-program]]
   is the same shape one size up.
6. **Stop the always-linked surface growing.**
   [[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]] —
   esp32c3 went 26 KB -> 50,528 -> 57,900 of code and ~70 KB -> 103,692 of bss,
   and x86_64-empty grew +4,025 in the same window. **Its canary was
   re-baselined rather than fixed**, to clear a red for a full-green pin, so the
   growth is currently unwatched.
   [[bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal]]
   is one named mechanism for it.
7. **Get the ESP suite into a tier.**
   [[bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it]]. Every
   number above is a hand measurement; nothing defends them.

# Two claims to keep straight

From `devdocs/dev/the-goal-cross-cross.md`: **"pxx runs on ESP32" is TRUE and
"pxx compiles Python to ESP32" is FALSE.** No `.npy` has ever run on a cross
target. Nothing in this umbrella changes that, and a rung that shrinks an image
must not be written up as if it had.

The bare profile's single RWX IRAM region is **qemu's shape** (`defs.inc:2275`:
*"qemu's esp32c3 machine models it as one RWX region"*), not a real C3's. Numbers
measured under `--esp-profile=bare` are numbers about qemu. The IDF profile,
where `.text` stays in flash, is the one that answers the owner's question — and
it is a single branch away.
