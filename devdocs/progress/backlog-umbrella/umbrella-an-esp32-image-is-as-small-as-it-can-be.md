---
slug: umbrella-an-esp32-image-is-as-small-as-it-can-be
title: "An ESP32 image is as small as it can be — code and constants in flash, SRAM spent only on what is live"
track: A
prio: 70
type: umbrella
blocked-by: [bug-a-a-static-nilpy-program-links-the-runtime-eval-interpreter, bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program, bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work, bug-a-dce-refuses-every-target-except-x86-64, feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident, bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss, bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok, bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss, bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal, bug-a-the-heap-arena-reserves-256-mib-without-map-noreserve-so-a-small-guest-cannot-run-any-allocating-pxx-program, bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it, feature-a-unreferenced-class-rtti-keeps-every-method-alive, bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]
status: new
created: 2026-09-18
owner: ""
summary: "Owner-set target 2026-09-18: same goal as [[umbrella-a-hosted-program-is-as-small-as-it-can-be]], on ESP, where it is the difference between running and not. RUNG 0 IS ANSWERED (2026-09-18): IDF costs 69,476 B of a C3's 409,600 and leaves **340,124 bytes** of free heap for a non-networking app, ~285,100 projected with WiFi linked — measured here with IDF v6.0.1 under the Espressif qemu, no chip needed. So the budget IS a number, and our NilPy hello-world's 146,612 B of data+bss is 43% of it. The runtime WiFi-buffer term he named still needs a chip (qemu has no radio model). Four facts frame it. (1) `--esp-profile=bare` loads code+data+bss into IRAM at $40380000 with a 256 KiB region, because qemu's esp32c3 machine models it as one RWX region (defs.inc:2275) — that is a QEMU shape, not a chip shape; the DEFAULT IDF profile keeps .text in flash. (2) SUPERSEDED 2026-09-20 -- `--dce` runs on every target but wasm32 now and BOTH ESP demos boot with it: C3 image 3,326,224 -> 2,307,648 B (-31%), S3 3,246,288 -> 1,996,848 B (-38%). That is a flash win and still not a RAM win, and neither reaches the stock 1 MB partition, which needs -66%. What the remaining 2 MB IS, measured per unit: pylib 53.6% / pyeval 30.1% on riscv32 (47.5% / 39.3% on xtensa) -- a runtime eval() tree-walker whose own header says it is NOT auto-used by NilPy is the second largest component of a program that never calls eval. (3) There is NO .rodata anywhere in the compiler — `grep -c rodata` is 0 in elfwriter.inc and defs.inc — so no constant can be flash-resident by construction. (4) The escape that would shrink an ESP image, `-uPXX_MANAGED_STRING`, SILENTLY EMITS AN EMPTY IMAGE on the bare path and reports `ok:`. That is the urgent one."
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

**Who is on it (2026-09-20): frankS holds the RUNGS, not the umbrella** — this
file's own rule, and it is the right one even when a coordinator hands the
whole thing over. Held: the pyeval rung and the riscv32/xtensa body-count rung
named under rung 3. Everything else here is unclaimed.

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
- **Both of those are fixed now.** The alt stack went first (−32,792 B of bss
  on every ESP image); the readln line buffer followed and is measured on its
  own baseline, 70,936 -> 66,848 on all four bare SoCs. What is left is
  dominated by the 64 KiB heap arena, which is a knob
  (`-dPXX_ESP_HEAP_8K` .. `_128K`) and not waste.

**RUNG 0 IS NOW MEASURED (2026-09-18, frankS) — the budget is a number:**

- **IDF costs 69,476 B of the C3's 409,600.** Its own `hello_world`, built here
  with IDF v6.0.1 for esp32c3 and booted under the Espressif qemu, links
  46,144 B of DRAM and prints `Minimum free heap size: 340124 bytes`.
  **340,124 B is ours to spend** with no networking linked.
- **Linking WiFi costs 55,024 B of heap pool before a single buffer is
  allocated** (`heap_init` RAM region 215,504 -> 160,480; static DRAM
  46,144 -> 101,352). A networking image projects to ~285,100 B free.
- **So our NilPy hello-world's 146,612 B of data+bss is 43% of the no-network
  budget and 51% of the WiFi-linked one. It fits in both, with room.**
- **Still not measured, and it is the half he named: the RUNTIME WiFi buffers.**
  qemu's esp32c3 has no WiFi radio model — the instrumented station build hangs
  in `esp_wifi_init()` and never reaches its heap print. That term needs a chip;
  55,024 B is a LOWER BOUND on the networking case.

See [[measure-what-idf-itself-costs-in-sram-on-a-c3]] for the method and the
two traps it walks past (`idf.py size`'s "Total" is not the chip's SRAM, and the
static table cannot see the 10,584 B startup allocates).

# The rungs

0. **DONE 2026-09-18** — [[measure-what-idf-itself-costs-in-sram-on-a-c3]].
   The budget is **340,124 B** without networking, ~285,100 B with WiFi linked.
   Every rung below is gradeable against that now. The runtime WiFi-buffer term
   still needs a chip.
1. **Make size measurable at all.**
   [[bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work]].
2. **Stop the silent-empty-image bug.**
   [[bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok]] —
   urgent, prio 75. The one flag that would shrink an ESP image today produces a
   well-formed ELF that does nothing and says `ok:`.
3. **DONE 2026-09-19/20 — the target has a stripping pass.**
   [[bug-a-dce-refuses-every-target-except-x86-64]] is five-of-six done and
   wasm32 is the only architecture left refused;
   [[bug-a-dce-drops-a-called-body-on-the-riscv32-idf-profile]] was the last
   wall on the ESP profile. Both demos build AND BOOT with `--dce`, output
   unchanged: **C3 -31%, S3 -38%** of the flashed image. It buys ZERO bytes of
   data or bss, exactly as the note above says — do not re-sell it as the RAM
   answer.
   **What it leaves is now attributed per unit, which is where the next rungs
   come from:**
   [[bug-a-a-static-nilpy-program-links-the-runtime-eval-interpreter]] (pyeval
   is 30.1% of the riscv32 image / 39.3% of xtensa's, and `PyHostCall` alone is
   109,396 B) and
   [[bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program]]
   (riscv32 keeps 122 bodies xtensa drops, **381,416 B, 18% of its image** —
   the stub-target root rule firing on one ISA and not the other).
   **And the instrument that is missing is named in the first of those:**
   `--dce-report` says which bodies DIED; nothing says why one LIVED. Without
   that, shrinking the 2 MB is guesswork.
4. **Put constants in flash.**
   [[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]].
   This is the owner's first directive and **this is where it pays.**
5. **Stop reserving SRAM for opted-out facilities.**
   [[bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss]] — 32 KB,
   8% of a C3's usable SRAM, for a facility the program said no to.
   **AND THE READLN LINE BUFFER, DONE 2026-09-18: −4,088 B of bare ESP bss on
   all four SoCs** (70,936 -> 66,848, size canary, esp32 / esp32c3 / esp32s2 /
   esp32s3 alike), and −8,168 hosted x86-64 where the SAME buffer was reserved
   TWICE. It was 4,096 bytes reserved by the Pascal driver in every image on
   every target — including ESP, where the PAL refuses fd 0 and the buffer could
   never be read into. It is now a pointer to a demand-allocated growable block
   in `builtinheap.pas`, so a program that never touches stdin reserves nothing
   and a line longer than the buffer is read WHOLE instead of truncated with its
   tail left in the fd for the next readln to pick up as a phantom line.
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

From `devdocs/dev/the-goal-cross-cross.md`, and **SUPERSEDED IN A NAMED SCOPE
ON 2026-09-19/20**: *"pxx compiles Python to ESP32" is FALSE* and *no `.npy` has
ever run on a cross target* were both true when written. A NilPy program now
runs on the **ESP32-C3 and ESP32-S3 under ESP-IDF, UNDER QEMU** (`nilpy-c3`,
`nilpy-s3`), and a second one drives a GPIO pin and takes an ESP-IDF timer
callback (`nilpy-hw-c3`, `nilpy-hw-s3`). **NO CHIP HAS RUN EITHER.** Bare metal
is still walled by design. So the sentence a rung must not overclaim has
MOVED rather than gone: it is now silicon, not the language.

The bare profile's single RWX IRAM region is **qemu's shape** (`defs.inc:2275`:
*"qemu's esp32c3 machine models it as one RWX region"*), not a real C3's. Numbers
measured under `--esp-profile=bare` are numbers about qemu. The IDF profile,
where `.text` stays in flash, is the one that answers the owner's question — and
it is a single branch away.

## OWNER: MEASURE SRAM, NOT IMAGE SIZE (2026-09-20, relayed by frankuser)

His words, relayed secondhand: *"about memory use - SRAM here is most relevant,
ESP's have 'plenty' flash memory so that's a lesser issue."*

**So the headline number for this umbrella is SRAM: data + bss + the heap arena.**
Image size is secondary and belongs in the same report as the second number, never
as the first.

**This RE-READS last night's results rather than retiring them.** `357d13162`
(-31%/-38%) and `6c211e043` (xtensa live code -52%) are **FLASH wins**: `.text`
lives in flash on the IDF profile. They are real and they are not what this
umbrella is ranked on.

**Every rung under here must say WHICH it measured** — several currently say
"image" without distinguishing. A rung reporting only an image delta has not
reported against this umbrella's own criterion.
