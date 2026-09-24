---
slug: bug-b-the-scheduler-s-default-coroutine-stack-does-not-fit-an-esp32
track: B
tags: [S]
type: bug
prio: 35
status: open
owner: ""
created: 2026-09-24
found-by: frankH (running the windowed CoSwitch on an ESP32-S3)
blocked-by: []
summary: "MECHANISM: lib/rtl/scheduler.pas sizes every Spawn'd coroutine stack with one constant, CO_STK = 192 KB, chosen for hosted Linux where a stack is mmap'd address space. On the ESP-IDF profile a stack is real heap from internal RAM (PXXAlloc is calloc there), so N coroutines cost N x 192 KB, and a program with three of them exhausts an ESP32-S3 without PSRAM: the unmodified test/test_scheduler.pas aborts under S3 QEMU with `pxx: out of memory (ESP-IDF heap exhausted)`. SpawnSized with 16 KB runs the same shapes correctly on the board. WHAT WOULD SPRING IT: any Spawn (not SpawnSized) of more than one coroutine on an ESP target. Fix direction: a per-platform CO_STK (FreeRTOS task stacks are single-digit KB), with the stack canary already present to catch an overflow."
---

# The scheduler's default coroutine stack does not fit an ESP32

## Measured (2026-09-24, HEAD after the windowed CoSwitch)

**Setup.** test/test_scheduler.pas (three `Spawn` calls), built with only
`--target=esp32s3` and booted under S3 QEMU (-m 4M, no PSRAM).

**Result.** It prints nothing and aborts:

    pxx: out of memory (ESP-IDF heap exhausted)

The message is from builtinheap's ESP-IDF branch.

**Control.** The same three shapes pass on the real board with
`SpawnSized(..., 16384)`:
- the file is test/test_scheduler_yields_deep_in_a_call_chain.pas;
- it recurses 20 frames deep before each yield;
- it matches the x86-64 oracle.

So the context switch is fine. The default stack size is the problem.

## Not the ABI

The call0 build hits the same arithmetic. It only never ran on IDF, because
IDF could not call a call0 object before 2026-09-24.
