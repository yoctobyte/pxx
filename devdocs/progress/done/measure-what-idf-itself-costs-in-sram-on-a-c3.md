---
slug: measure-what-idf-itself-costs-in-sram-on-a-c3
title: "Rung 0: what does IDF itself cost in SRAM on an ESP32-C3 — MEASURED, the budget is 340,124 bytes"
track: A
tags: [S]
prio: 70
type: measure
blocks: [umbrella-an-esp32-image-is-as-small-as-it-can-be]
status: done
created: 2026-09-18
owner: frankS
summary: "ANSWERED 2026-09-18. The owner asked on 09-17: 'does this include what IDF uses? (because likely network buffers etc do eat up some).' Measured with the IDF v6.0.1 and Espressif toolchain already on this box, esp32c3, under the Espressif qemu — no chip needed. IDF's own `hello_world` links 46,144 B of DRAM and leaves **340,124 bytes of free heap at app_main** (its own `esp_get_minimum_free_heap_size()`), i.e. IDF costs **69,476 B of the C3's 409,600**. Linking the WiFi station example instead takes static DRAM to 101,352 B and shrinks the heap_init pool by **55,024 B**, so a networking image has ~285 KB before `esp_wifi_init()` allocates a single buffer. THE DENOMINATOR NOW EXISTS: our NilPy hello-world's SRAM demand (data+bss = 146,612 B) is **43% of the no-network budget and 51% of the WiFi-linked one** — it fits in both, with room. That retires 'we do not know how much of it is ours to spend' and it retires the retracted claim that a Python program is 6.6x over. WHAT IS STILL NOT MEASURED, and it is the owner's exact words: the RUNTIME WiFi buffers. qemu's esp32c3 has no WiFi radio model and the station example hangs at `esp_wifi_init()`, so that term needs a chip. The 55,024 B above is the LINK-TIME cost only and is a lower bound on the networking case."
---

# What was asked

> *"does this include what IDF uses? (because likely network buffers etc do eat
> up some)."* — the owner, 2026-09-17

Rung 0 of [[umbrella-an-esp32-image-is-as-small-as-it-can-be]]. Until it had a
number, no rung of that umbrella could claim an image fits, because "149 KB for
nothing" had no denominator.

# How, and why it needed no chip

`pxx --doctor` already says this box has ESP-IDF (`/home/neo/esp/esp-idf`,
v6.0.1) and the Espressif toolchain (`/home/neo/.espressif`), and the toolchain
ships `qemu-riscv32` with an `esp32c3` machine. So the measurement is an IDF
build plus a boot, entirely local.

    idf.py set-target esp32c3 && idf.py build && idf.py size
    qemu-system-riscv32 -M esp32c3 -drive file=qemu_flash.bin,if=mtd,format=raw ...

**Read the serial log, not `idf.py size` alone.** The static table is a
link-time accounting of `321,296 B` of "DRAM"; the chip has 400 KiB of SRAM and
hands out four separate pools. Only the boot log says what is actually left.

# The numbers

Static, `idf.py size`, esp32c3, IDF v6.0.1:

| build | Flash `.text` | Flash `.rodata` | DRAM total | DRAM `.text` | `.data` | `.bss` |
| --- | --- | --- | --- | --- | --- | --- |
| `hello_world` | 55,146 | 23,236 | **46,144** | 36,372 | 5,932 | 3,840 |
| `wifi/getting_started/station` | 552,838 | 98,872 | **101,352** | 70,856 | 13,184 | 17,312 |

Runtime, from the boot log's own `heap_init` lines:

| build | RAM | Retention | Retention | RTCRAM | pool total |
| --- | --- | --- | --- | --- | --- |
| `hello_world` | 215,504 | 116,496 | 10,576 | 8,132 | **350,708** |
| `station` | 160,480 | 116,496 | 10,576 | 8,132 | **295,684** |

And the figure that settles it, printed by the example itself:

    Minimum free heap size: 340124 bytes

So **startup (main_task stack and friends) costs 10,584 B** beyond the pools,
and **IDF's total SRAM cost for a do-nothing app is 409,600 - 340,124 =
69,476 B — 17% of the chip.**

# The answer to the question as asked

**Ours to spend: 340,124 bytes** with no networking linked.

Linking WiFi costs **55,024 B of pool** before any buffer is allocated
(`215,504 -> 160,480`), which tracks the +55,208 B static DRAM delta to within
alignment. Applying the same 10,584 B startup overhead projects **~285,100 B**
free at `app_main` for a networking image — marked as a PROJECTION because the
station example never reaches its own heap print (below).

Against that budget, our NilPy `print("hi")` needs `data+bss = 146,612 B`
(i386 and arm32, identical; 152,880 on x86-64):

- **43.1%** of the no-network budget
- **51.4%** of the WiFi-linked projection

It fits in both.

# What is NOT measured, and it is the half he named

**The runtime WiFi buffers.** qemu's `esp32c3` machine has no WiFi radio model;
the instrumented station build boots, prints `heap_init`, and then stops at
`eFuse: calibration efuse version does not match` and never returns from
`esp_wifi_init()`. Both `RUNGZERO` heap prints were added and neither was
reached. **That term needs a chip**, and the 55,024 B above is a LOWER BOUND on
the networking case, not the answer to it.

# Two traps this measurement walks past, recorded so the next one does too

- **`idf.py size`'s "Total 321,296" is not the chip's SRAM.** It is the DRAM
  window the linker scripts account against. The C3 has 409,600 B and hands out
  four pools including retention RAM and RTCRAM. Quoting the static "Remain"
  column understates the budget by ~20 KB.
- **The static table cannot see startup.** 10,584 B of the difference between
  the pool sum and the reported free heap is allocated after `heap_init` and
  before `app_main`. A rung graded on `idf.py size` alone would claim 10 KB it
  does not have.

# Consequence for the umbrella

The budget is a number now, so the rungs are gradeable. And the direction is
the opposite of what the rejected Track U escalation assumed: **the SRAM
question is not "does it fit" but "how much headroom is left for the heap"** —
147 KB static leaves ~193 KB of heap on a non-networking C3, which is where the
interesting work is.
