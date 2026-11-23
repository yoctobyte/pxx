---
slug: bug-a-a-dce-cut-backward-call-keeps-its-old-target-and-recurses-on-esp
track: A
prio: 90
type: bug
status: done
created: 2026-11-23
found-by: rfid project (ESP32-C3 hardware, json.loads); reduced and fixed by claude-pxx
tags: [esp, dce, riscv32, xtensa, regression]
blocked-by: []
summary: "Done 2026-11-23. On ESP, freeing any class with a managed field (a string field is enough) recursed in PXXClassFinalize until a stack protection fault or the watchdog; json.loads never returned. Since 10442bd0be (2026-11-20). DceCutCalls re-aimed a cut call's ProcIdx but not its CallFixTarget, which ApplyCallFixups prefers; PXXClassMgmtRun is defined just before PXXClassFinalize, so that call was a backward one with a recorded target, and after compaction the old address was PXXClassFinalize's own entry. The cut now clears CallFixTarget."
---

# A DCE-cut backward call kept its old target and recursed on ESP

## Symptom

rfid project, ESP32-C3 v0.4 hardware, latest channel latest-4c6195305e:
`json.loads('{"a":1}')` printed nothing more and then hit a "Stack
protection fault" in task main, with every frame in PXXClassFinalize. Under
Espressif QEMU, `json.loads('1')` resets on the watchdog on the C3 and hangs
on the S3, and so does a plain Pascal program that frees a class with an
AnsiString field (test/esp_free_a_class_with_a_string_field.pas). Linux
riscv32, arm32 and i386 are fine, because the cut runs only where
DceClassSlotsWithholdable holds.

## Cause

10442bd0be added `DceCutCalls('PXXClassFinalize', 'PXXClassMgmtRun', ...)`,
which drops the management-operator walk when no descriptor has kind 8.
DceCutCalls set `CallFix[i].ProcIdx := nop` and left `CallFixTarget[i]`.
For a call to a body that was already emitted (a backward call),
CallFixTarget holds that body's address, and ApplyCallFixups uses it
before the proc row. PXXClassMgmtRun sits just above PXXClassFinalize. Once
it and PXXClassInitialize were dropped, the remapped old address was
PXXClassFinalize's own first byte: `jal PXXClassFinalize` from inside
PXXClassFinalize (riscv32 object, offset +0x14e). Every older cut points
forward, which is why none of them did this.

Bisected: 10442bd0be^ frees cleanly under QEMU, and HEAD did not.

## Fix

DceCutCalls clears CallFixTarget[i] with the ProcIdx, so the site resolves
through PXXDceNoCall's row. The call is now `jal PXXDceNoCall`. The probe
and json.loads work on both chips under QEMU.

## Tests

- test-core: tools/check_rv32_no_self_call.py reads the riscv32 ESP object
  (no toolchain needed) and fails if PXXClassFinalize or
  PXXClassFinalizeManaged calls its own entry. It fails on HEAD without the
  fix and passes with it.
- test-esp-idf: the probe under QEMU on esp32c3 and esp32s3 has to print
  `PXX-free freed`.
