---
slug: bug-a-xtensa-entry-jump-cannot-reach-a-main-body-past-128kb
track: A+S
prio: 55
type: bug
blocked-by: []
status: backlog
summary: "The xtensa program entry stub ends in a bare `j` to the main body, which sits past every unit body. Xtensa's J reaches +-128 KiB, so any xtensa image with more than 128 KiB of unit code cannot be entered. It is now a hard compile error rather than a silent mis-jump; making it WORK needs a reach-independent entry jump. Blocks xtensa under ESP-IDF."
---

# The xtensa entry jump cannot reach a main body past 128 KiB

## Shape

`EmitProgramEntryForTarget` (ir_codegen.inc) ends the xtensa entry stub with a
patchable `xtensa_j(0)`, and `PatchProgramEntryJump` fills it in with
`EncodeXtensaJ(CodeLen - jmpPatch)`. The main body is emitted **after** every
unit body — the jump exists precisely to skip over them — so its distance grows
with the whole program's unit code.

Xtensa's `J` has an 18-bit signed byte field: **±128 KiB**. Past that the jump
cannot be encoded at all.

Since [[bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset]]
this is a clean diagnostic instead of a mid-instruction crash:

```
error: target xtensa: j displacement 262581 is outside the encodable range
       -131072..131071; the code is too large for this branch form
```

## Repro

Needs a large xtensa image, which today means the IDF profile plus a full RTL:

```
$ ./compiler/pascal26 --target=xtensa --xtensa-abi=windowed --platform=esp \
    --no-signals -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp \
    examples/esp32/timer-c3/main/main.pas /tmp/main.o
```

with the one-line profile fix from
[[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]] applied. That
program's main body sits 262591 bytes past the entry stub — 2x the reach.

## Why only xtensa

Every other backend's entry branch has room: aarch64 `b` is ±128 MiB, arm32 `b`
±32 MiB, riscv32 uses `EncodeRISCVJAL` (±1 MiB), x86-64 a rel32. riscv32 under
the identical IDF profile builds and runs the same program today — its image is
239-345 KB and its JAL reaches. **xtensa is the only target whose entry branch
is narrower than a realistic image.**

## Options, none free

1. **`l32r` + `jx`.** The literal-pool machinery already exists
   (`XtensaEmitLitHeader`, and `IR_PROCADDR` already materialises an absolute
   code address via an ELF-patched literal + `ProcAddrFix`). But the main body
   is not a proc, so it needs either a new "absolute address of a code offset"
   fixup in the ELF writer, or a PC-relative variant. `xtensa_jx` does not exist
   yet and its bytes must be verified against `xtensa-esp-elf-as`, per this
   file's own convention — the encoders here were byte-verified, not derived
   from the manual.
2. **PC-relative, no relocation.** `call0 .+4` leaves the PC in `a0`, so
   `l32r` a code-relative delta and `add`. Needs no fixup at all, but clobbers
   `a0` — the windowed return address at entry — so it must be saved and
   restored. ~6 instructions.
3. **Emit the main body first.** Then the entry jump is ~0 and the main body's
   calls to unit bodies become forward `call8`s, which reach ±512 KiB — 4x the
   headroom. Cleanest result, most invasive change: emission order is shared
   across every frontend driver.

Whichever is chosen, **keep the short `j` when it fits**: bare-metal images are
SRAM-bounded at tens of KB and are covered by a byte-identity canary, so the
long form should not perturb them.

## Why it matters now

It is the last thing between xtensa and the ESP-IDF route. With the profile fix
applied and this bug present, `--platform=esp` on esp32s3 compiles everything
else correctly: `UpCase`, `Str`, `Pos`, `Int64->float` all lower, and the image
reaches 261311B. Only the entry jump fails. The user's hardware is S2/S3
(xtensa), and the IDF-linked route is the one that carries FreeRTOS tasks, IDF
drivers, VFS file I/O and sockets — *"the IDF-linked route is more interesting
than the bare metal route, bare tests the compiler but misses out on a lot of
functionality"* (2026-08-27).

## Gate

`tools/esp_run.sh --chip esp32s3` on `examples/esp32/timer-c3/main/main.pas`
printing the seven `PXX timer:` lines, matching esp32c3's, with the profile fix
applied — plus the bare images staying byte-identical.
