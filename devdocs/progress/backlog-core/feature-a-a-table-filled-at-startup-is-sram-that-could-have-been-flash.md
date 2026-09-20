---
slug: feature-a-a-table-filled-at-startup-is-sram-that-could-have-been-flash
track: A
prio: 45
type: feature
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "On ESP-IDF our SRAM is .data + .bss, and .bss is the LARGER half -- 89,352 B of 125,832 on the NilPy print demo, 71%, measured 2026-09-20 with build.sh's sram mode. The read-only-segment work cannot touch .bss by construction: a section with no file contents has nothing to place in flash. But a table that is CONSTANT AFTER INITIALISATION and reached .bss only because it is written by startup code is not really mutable data -- it is a constant paying twice, once in SRAM for the zeroed slot and once in code for the fill loop. Baking such a table into .rodata instead removes both. THE POPULATION IS NOT ESTABLISHED and that is the first task: nothing currently distinguishes `filled once at startup and never written again' from `written during the run', and a.datamap reports .bss as one unattributed lump. tools/... a.constdata already names the Pascal typed-const arrays that DID get promoted, and its own useful signal is the arrays that did NOT -- promotion is all-or-nothing per array and fails closed -- so the refusal population is a place to start looking, not the answer. NOT on the read-only-segment ticket's REMAINING list, and larger than everything on it: that list's named items measure at 32 bytes on this program."
---

# A table filled at startup is SRAM that could have been flash

Filed 2026-09-20 out of the ESP SRAM measurements under
[[umbrella-an-esp32-image-is-as-small-as-it-can-be]]. It is **not** an item on
[[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]]'s
REMAINING list, and on the evidence so far it is worth more than all of them.

## Where the bytes are

NilPy print demo, riscv32, `--platform=esp --dce`, measured on the chip under
qemu with `examples/esp32/nilpy-c3/build.sh sram`:

```
SRAM 125,832 B   =  .data 36,480  +  .bss 89,352
                                      ^^^^^^ 71%
free DRAM pool 211,296 B
```

`PXXDBG=a.datamap` on the same object breaks the DATA segment down and shows
the named candidates are tiny — prop/meth arrays and IMTs together are **32
bytes** — while `.bss` is reported as one lump with no categories at all.

## The claim, and the part of it that is not established

**Established:** read-only placement cannot move `.bss`. A `NOBITS` section has
no file contents; there is nothing to put in flash. Every byte of the 89,352 is
either genuinely mutable or is something else.

**The hypothesis:** a meaningful share of it is *constant after
initialisation* — a table that lands in `.bss` because startup code writes it,
not because the program ever writes it again. Such a table pays twice: a zeroed
SRAM slot, and the code that fills it. Emitting it into `.rodata` with its
final contents removes both costs at once.

**NOT established, and it is the whole first task: the population.** Nothing in
the compiler currently distinguishes "written once by init code" from "written
during the run", and `a.datamap` does not categorise `.bss` at all. **A number
for this ticket does not exist yet and none should be quoted until it does.**

## Where to start, and one thing that is NOT the answer

`PXXDBG=a.constdata` already reports Pascal typed-const arrays that were baked
into `.data` rather than filled by startup code, and its documented useful
signal is the arrays that are **absent** — promotion is all-or-nothing per
array and fails closed, so silence means one element was not a plain literal
and the whole array stayed on the fill-it-at-startup path.

**That refusal population is a place to look and is not the same question.**
`a.constdata` is about Pascal `const` arrays with literal initialisers. This
ticket is about anything constant-after-init, including runtime tables the
compiler or the RTL builds, which no `const` declaration names. Treating the
`a.constdata` refusals as the population would be a census whose filter
restates a hypothesis it was not built for.

The honest first step is to extend `a.datamap` to attribute `.bss` the way it
attributes `.data` — per allocating site, via `AllocateSymOffset` — and see
what the large rows actually are. **Measure before designing:** a category that
turns out to be 4 KB is not worth a mechanism.

## The ESP constraint that applies to every candidate

From frankH, 2026-09-20, and it outranks the byte count: **can an ISR reach
this structure with the flash cache off?** ESP objects deliberately keep class
RTTI and Pascal VMTs in `.data` for exactly that reason. Any table moved to
flash acquires that hazard, so the per-item question is reachability first and
size second.
