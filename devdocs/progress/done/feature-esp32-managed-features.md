# ESP32 managed-feature port (xtensa + riscv32, qemu-validated)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-17
- **Commits:** ae9727f, 84ceb95, 54bc954, e28857c, 8152eac, a346c2b, bb23475,
  239ccc2, 8256282

## Motivation

Stage-1 ESP codegen (done/feature-target-esp32) only ran procs/params/calls/
loops/ifs/globals/int arith. This arc brings the managed-runtime spine to both
ESP ISAs and, critically, establishes a **runnable output-equality harness** so
ESP features are validated against the x86-64 oracle on real Espressif QEMU,
not just llvm-mc encodings.

## What landed

**Harness.** `tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>` compiles for
the chip's ISA, links it as `app_main` via `examples/esp32/hello-{s3,c3}`,
merges a flash image, boots it under the Espressif `qemu-system-{xtensa,riscv32}`
fork, and prints exactly what `app_main` wrote (IDF banner + trailing qemu
signal stripped, serial CRLF→LF). Output is diffed against the program's x86-64
run. Heavy / env-dependent (needs `. ~/esp/esp-idf/export.sh`), so NOT in
`make test`.

**Codegen / runtime, both ESP backends (unless noted):**
- Native `div`/`mod` — xtensa `quos`/`rems` (LX7, esp-as encodings; llvm-mc
  lacks them) + SAR shifts `ssl/sll`,`ssr/srl`; riscv already had M-extension.
  Baseline = S2+/Cx+; LX6 soft-fallback deferred (feature-esp-isa-baseline-
  softfallback).
- **Xtensa windowed-ABI constant-sp fix** — the codegen moved `sp` for a manual
  expression stack, desyncing the window spill area at `[sp-16]` past 4-deep
  calls (Guru Meditation). Now keeps `sp` constant: expression stack in a
  reserved frame region (sp-relative, `XtSpillDepth`), `entry`+`addmi` one-shot
  frame, bare `retw`. Unblocked all nested/recursive Pascal on real S3.
- Heap: static-arena `HeapMmap` (64 KiB BSS, no mmap); `New`/`GetMem`/`Dispose`;
  `IR_TERMINATE` (early Exit / AN_HALT self-loop).
- Dynamic arrays: lean unmanaged-element `PXXDynSetLen`; `SetLength`/`Length`/
  index; `IR_LEA` derefs local dynarrays + open-array value params to the handle.
- `array of const` writeln: `IR_DEFAULT_MEM`→`PXXMemZero`, `IR_SLOTADDR`,
  TVarRec vector build, `Length`/field over the open-array param.
- `Ord`/`Chr`/`Integer()`/`LongWord()` type-pun passthroughs.

## Validated (qemu, both esp32s3 + esp32c3, == x86-64 oracle)

`test_esp_{print,hello,heap,dynarray,aoc,cast}.pas` —
ints/recursion (`1..5`/`15`), fixed bytes (`PXX/OK`), heap (`100/20/3/123`),
dynarrays (`5/150/2/30`), array-of-const writeln (`1 2 3` / `42 -7 100 999`),
casts (`ABZ!`). `make test` + self-host byte-identical after every step.

## Acceptance

- Both ESP ISAs run the managed-feature spine (heap → dynarrays → array-of-const
  → portable writeln) under Espressif QEMU with output identical to x86-64. ✓
- Repeatable harness (`tools/esp_run.sh`). ✓

## Notes / follow-ups

- **Managed strings** (`tyAnsiString`, the PXX default — `PXX_MANAGED_STRING` is
  seeded by `PasInitDefines`) are NOT yet ported: the `PXXStr*` runtime is
  guarded out on ESP, so `s := 'lit'` stores the frozen-literal pointer and
  `Length` reads junk. Tracked in feature-esp32-managed-strings.
- Records-by-value, classes/VMT, sets, exceptions, RTTI on ESP — later.
- Real-hardware flash (vs qemu) — feature-esp32-idf-xtensa.
