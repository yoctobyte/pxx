---
slug: decide-what-a-static-python-program-on-a-microcontroller-needs-to-write-to
track: U
prio: 50
type: decide
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "Every NilPy ESP image carries FIVE 4,128-byte text records -- Input, Output, ErrOutput, StdOut, StdErr -- totalling 20,640 B, which is 23% of its .bss and 16% of its whole 125,832 B of SRAM, in a program that never opens a file and on a chip where SRAM is the scarce resource. Measured 2026-09-20 with PXXDBG=a.datamap on examples/esp32/nilpy-c3. THE FORK IS NOT TECHNICAL AND THAT IS WHY IT IS HERE: what should a static Python program on a microcontroller be able to write to? Every answer is implementable and they differ in what we are trying to be -- a Python whose programs behave the same everywhere, or an embedded target that gives you what the chip can afford. Options: (a) keep all five, standard behaviour, 20,640 B; (b) keep stdout/stderr only, drop Input/Output/the file machinery on ESP; (c) shrink the per-record buffer on ESP (4,128 B is a 4 KiB buffer plus header, sized for a filesystem, not a UART); (d) allocate a record's buffer on first use so an unused stream costs a header. Recommendation: (c)+(d) -- it keeps every program working, and a line-buffered UART does not need 4 KiB."
---

# What does a static Python program on a microcontroller need to write to?

Filed as a `decide` rather than a bug because **every option works** and they
differ in what we want to be, which is the Track U test.

## The measurement

`PXXDBG=a.datamap` on `examples/esp32/nilpy-c3/main/main.npy`, riscv32,
`--platform=esp --dce`, compiler `c6c5f5f1b`:

```
bss 89,352B = 23,115B named globals + 66,237B unattributed

  bss 4128B  Input
  bss 4128B  Output
  bss 4128B  ErrOutput
  bss 4128B  StdOut
  bss 4128B  StdErr
  bss 1536B  TokCache
  bss  512B  FreeBins
```

**20,640 B — 89% of all named globals, 23% of `.bss`, 16% of our 125,832 B of
SRAM.** The program is a class, a list, a loop and `print`. It opens no file
and reads no input.

4,128 is a 4 KiB buffer plus a 32-byte header — a size chosen for a
filesystem. The ESP console is a line-buffered UART.

## The question, in goal terms

> **Should a Python program compiled for a microcontroller have the same five
> standard streams as one compiled for Linux, at 4 KiB of SRAM each — or should
> an embedded target give it what the chip can afford?**

Answerable without knowing what a text record is, which is the test for whether
this belongs here at all.

## Options

- **(a) Keep all five as they are.** A program behaves identically on every
  target; `Input` works if someone wires a UART reader. Costs 20,640 B, ~10% of
  the free DRAM pool.
- **(b) Drop `Input` and `Output` on ESP, keep `StdOut`/`StdErr`.** Saves
  ~12 KB. Changes behaviour: a program reading `input()` stops compiling or
  stops working, and that divergence is per-target.
- **(c) Shrink the per-record buffer on ESP.** 256 bytes a record saves
  ~19 KB and every program still works. A UART is line-buffered, so the buffer
  is latency, not correctness.
- **(d) Allocate the buffer on first use.** An unused stream costs a header;
  a used one costs what it always did. Composes with (c).

**Recommendation: (c) + (d).** No program stops working, the divergence is a
buffer size rather than a missing stream, and it is the only pair that costs
nothing in behaviour.

## What is NOT being asked

Not whether `writeln` works on ESP-IDF — it does, and the IDF stdio path is
already wired. This is only about what the streams RESERVE.

## Before implementing

**Re-measure.** 4,128 is one target's number on one program; check a Pascal ESP
image and the other chip before sizing anything, and state the saving as a
ceiling — dropping a record also frees the alignment after it, and keeping a
header keeps some of it.
