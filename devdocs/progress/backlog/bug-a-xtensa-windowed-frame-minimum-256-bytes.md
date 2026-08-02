---
track: A
prio: 55
type: bug
summary: "Every windowed-ABI stack frame costs at least 256 bytes — a fixed expression region plus the 256-byte granularity of the single ADDMI the prologue patches — so ~11 nested calls exhaust ESP-IDF's default 3584-byte task stack. Printing one Int64 digit by digit does it."
---

# xtensa windowed: every frame costs ≥256 bytes, so recursion dies early on IDF

- **Type:** bug (resource, not a wrong value — but it presents as
  `LoadProhibited` with no diagnostic) — **Track A** (xtensa prologue /
  frame layout), Track S campaign
- **Found:** 2026-08-02, running `test/test_esp_hw_validation.pas` on esp32s3

## Symptom

```pascal
procedure PutIntRec(n: Int64);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + Integer(n mod 10));
end;
```

Printing `922337203685477580` (18 digits, so 18 nested frames) on esp32s3 under
ESP-IDF prints `922337` and then panics with `Guru Meditation Error ...
LoadProhibited`. Ten digits are fine. The identical program on esp32c3
(riscv32) prints all 18 — riscv32 frames are a fraction of the size.

## Cause

Two costs stack up, and both are paid by EVERY windowed frame:

1. **The constant-sp expression region.** Windowed code may not move `sp` (the
   window overflow handlers spill the caller's a0-a3 to `[sp-16]`), so
   temporaries live in a region reserved up front — `XT_EXPR_REGION`, a fixed
   192 bytes, whether the routine uses two slots or forty-eight. Plus
   `XT_OUTARG_REGION` (64) for outgoing stack arguments.
2. **ADDMI granularity.** The prologue reserves ONE patchable 3-byte slot and
   `PatchProcPrologue` fills it with `ADDMI`, whose immediate is a multiple of
   **256**. So the frame rounds up to 256 even when 64 would do, and 256 is the
   floor.

3584 (the IDF default main-task stack) / ~300 bytes per frame ≈ 11 frames.

## Two fixes, both contained

- **Small frames should patch `ADDI`, not `ADDMI`.** ADDI is the same 3 bytes
  and has a ±128 byte-granular immediate, so a frame that fits in 128 bytes can
  be exact. Halves the floor immediately.
- **Size the expression region per routine.** The offsets emitted are relative
  to the BOTTOM of the frame (outgoing area at sp+0, expression stack just
  above), and `PatchProcPrologue` runs AFTER the body is emitted — so the
  reservation can be the routine's actual `XtSpillDepth` high-water mark
  instead of the constant. Nothing needs to be re-emitted; only a max needs
  tracking in `XtensaPushA2` / `XtensaPush64`.

Together a leaf routine's frame should drop from 256 to well under 128.

## Workaround in place (not a fix)

`examples/esp32/*/sdkconfig.defaults` now set
`CONFIG_ESP_MAIN_TASK_STACK_SIZE=8192` and the same for the timer task, which
makes the case above pass. Any user project needs the same line — that is the
part worth removing.

## Caution for whoever takes this

`XT_EXPR_REGION` was 256 and is now 192 precisely so that adding
`XT_OUTARG_REGION` (64) keeps the total at 256 rather than crossing the rounding
boundary and DOUBLING every frame. Measured 2026-08-02: at 512 bytes per frame
the 19-deep print died where it now survives. Whatever replaces this arithmetic,
check the rounding, not just the sum.

## Acceptance

- A leaf routine's windowed frame is smaller than 256 bytes (read it off the
  patched prologue).
- `test/test_esp_hw_validation.pas` passes on esp32s3 with the STOCK 3584-byte
  task stack, i.e. after removing the `sdkconfig.defaults` override.
- Self-host fixedpoint + `make test-esp-bare` green; the qemu s3 windowed runs
  still match their oracles.
