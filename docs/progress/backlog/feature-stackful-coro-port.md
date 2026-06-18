# Port the stackful coroutine backend to all targets

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (design discussion — async ergonomics across targets)

## Motivation

The stackful coroutine backend (heap stack + context-switch primitive; `yield`/
`await` anywhere, managed locals across suspension, `try`/`except` across
suspension) is **x86-64 only** today — the context switch is hand-written asm
(`compiler/coroutine_emit.inc`). Every other target (i386, ARM32, AArch64,
RISC-V/esp32c3, Xtensa/esp32s3) can run only the stackless backend. That blocks:

- rich coroutines on hosted ARM/i386;
- the **cost-warning upscale** path of feature-async-auto-backend on ESP/32-bit
  (without a stackful backend there, ineligible async code must hard-error rather
  than fall back) — see
  [developer/concurrency-memory-model.md](../../developer/concurrency-memory-model.md).

Memory is **not** the blocker: the saved stack lives on the heap, allocated on
start and freed on completion, so even hundreds of live stackful coroutines are
affordable (cheaper than threads; trivial next to a MicroPython heap). The
blocker is purely the missing per-target context-switch primitive.

## Scope

Port the context-switch primitive (save callee-saved regs + sp + return address,
swap to the coroutine's heap stack, and back) per target. Once the first 32-bit
port is done, the rest are largely mechanical copies with the target's
callee-saved register set and ABI.

- **AArch64** (64-bit; hosted) — x19–x28, fp, lr, sp.
- **ARM32** — r4–r11, sp, lr (mind the [[project_arm32_alignment_landmine]]
  4-byte alignment rule).
- **i386** — ebx, esi, edi, ebp, esp.
- **RISC-V (esp32c3)** — s0–s11, ra, sp.
- **Xtensa (esp32s3)** — Call0 callee-saved set; the bare profile is Call0-only
  (no register windows) which keeps the switch simple — see the bare-boot notes.
- A **stack-size knob**: a sensible default plus a per-coroutine override (on ESP
  nobody else picks the size, and there is no guard page).

## Validation

Mirror the existing x86-64 coroutine/generator tests on each target; on ESP,
output-equality vs the x86-64 oracle under `tools/esp_run_bare.sh` /
`tools/esp_run.sh`. `make test` + `make cross-bootstrap` byte-identical after
each target.

## Acceptance

- A stackful generator/async routine (yield in a nested call frame; a managed
  local across the suspension) runs correctly on each ported target, output ==
  x86-64 oracle.
- Per-coroutine stack size is selectable; overflow behaviour documented (no MMU
  guard on ESP).
- Unblocks the cost-warning upscale in feature-async-auto-backend on the ported
  targets.
