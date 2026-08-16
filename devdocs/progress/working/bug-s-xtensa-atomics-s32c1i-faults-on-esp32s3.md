---
track: A
prio: 45
type: bug
blocked-by: []
status: working
owner: claude-acpn
---

# xtensa atomics: the encoders are right and `S32C1I` still faults on esp32s3

- **Type:** bug (missing codegen, blocked on one hardware question) — Track A
  (backend), **Track S** campaign (ESP32).
- **Split from** [[bug-a-riscv32-and-xtensa-have-no-atomic-codegen]] on
  2026-08-11, whose riscv32 half is done and verified under qemu. This is the
  xtensa remainder, filed for a **dedicated Track S session** because what is
  left is a hardware/emulator question rather than compiler work.
- **Not a regression:** xtensa still gives the same clean compile error it
  always did (`unsupported node in IR codegen: atomic`). Nothing was left
  half-applied — the codegen arm was written and deliberately REVERTED, because
  a hang is worse than an honest refusal.

## Where it stands — the compiler side is arguably finished

Already landed and in tree (`compiler/xtensaenc.inc`), byte-verified against
`xtensa-esp32s3-elf-as` rather than derived from the manual:

| encoder | instruction | bytes |
| --- | --- | --- |
| `xtensa_s32c1i(t, s, off)` | `s32c1i a4, a2, 0` | `00 E2 42` |
| `xtensa_wsr_scompare1(t)` | `wsr.scompare1 a3` | `13 0C 30` |
| `xtensa_rsr_scompare1(t)` | `rsr.scompare1 a3` | `03 0C 30` |
| `xtensa_memw` | `memw` | `C0 20 00` |

The sequence they were used in is in the git history of
`compiler/ir_codegen_xtensa.inc` (see the commit that reverted it) and is
straightforward: `S32C1I` stores only if the word still equals `SCOMPARE1` and
hands back the ORIGINAL word, so ADD/XCHG retry until what they read is what
they replaced, and CAS is a single attempt by definition.

Note the branch offset convention if you re-apply it: `xtensa_bne(s, t, off)`
measures `off` from the BRANCH instruction itself (`EncodeXtensaBranch`
subtracts the 4 the ISA adds). A retry loop over four 3-byte instructions is
**-12**; -15 walks back into the argument-pop sequence and loops forever with no
output at all.

## The blocking question

**`s32c1i` faults on `qemu-system-xtensa -M esp32s3`. Is that the memory REGION
or the emulator?**

Measured 2026-08-11, in this order:

1. the program hangs before printing anything — the atomic is its first
   statement, so nothing had run yet;
2. `-d int` shows a repeating `xtensa_cpu_do_interrupt(12)` at pc `0x400003c0`
   — an exception vector loop in ROM. Crucially **not** an
   unimplemented-instruction report: `-d unimp,guest_errors` says nothing;
3. removing ONLY the `s32c1i` and keeping `wsr.scompare1` lets the program run
   to completion — **so `wsr.scompare1` executes fine and `s32c1i` is the
   instruction that faults**;
4. the obvious hypothesis — the bare profile loads the whole image at the
   INSTRUCTION alias (`ESP_BARE_IRAM_BASE_XT` = 0x40378000) and `S32C1I` may
   require the DATA alias — is **untested, not disproved**: reading the same
   word through an assumed data alias (`addr - $6F0000`) answered 0, so that
   offset is simply wrong. The real S3 mapping needs looking up.

## The next step, and why it is this one

Build a **two-instruction `.S`** with the real toolchain and run it under the
same qemu:

```asm
    movi    a2, <some SRAM address>
    movi    a3, 0
    wsr.scompare1 a3
    movi    a4, 1
    s32c1i  a4, a2, 0        # does THIS fault, from gcc's own assembler?
```

That separates "our sequence" from "this emulator" in one step. If the real
toolchain's `s32c1i` faults at the same address, it is the region or the model
and no amount of codegen work helps; if it succeeds, the fault is ours and the
sequence is where to look.

Both halves of the environment are already installed on the dev box:
`~/.espressif/tools/xtensa-esp-elf/*/bin/xtensa-esp32s3-elf-as` and
`~/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa`.

Follow-ups depending on the answer:

- **region** → try the DATA alias for the atomic (and find the S3's real
  I/D offset), or place the atomic's target in a region that supports it;
- **emulator** → the codegen may still be correct for real silicon. Then this
  needs hardware to verify, and landing it blind is exactly what the reverted
  arm avoided. Say so in the ticket rather than shipping a hang.

## Scope, when it does land

Only the 32-bit ops: `ATOMIC_XCHG`, `ATOMIC_CAS`, `ATOMIC_ADD`. The `*64`
variants keep the honest refusal every 32-bit target gives.

No chip gate is needed: `S32C1I` is on every LX6/LX7 part Espressif ships,
single- and dual-core alike, so `SocHasAtomicISA` is true for all three xtensa
rows of the capability table and the xtensa arm never has to ask which chip.

## Gate

`test/test_esp_bare_atomic.pas` — already in tree, already used for the riscv32
half — booting under `qemu-system-xtensa -M esp32s3` with UART output matching
the x86-64 oracle, wired into `make test-esp-bare` beside the esp32c3 run.
Plus `make test` + self-host fixedpoint.
