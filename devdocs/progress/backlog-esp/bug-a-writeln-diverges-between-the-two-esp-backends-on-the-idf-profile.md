---
slug: bug-a-writeln-diverges-between-the-two-esp-backends-on-the-idf-profile
title: "writeln diverges between the two ESP backends on the IDF profile — xtensa silently drops it, riscv32 emits Linux syscalls"
type: bug
track: A
tags: [S]
prio: 70
status: new
found: 2026-09-18
blocks: [umbrella-an-esp32-image-is-as-small-as-it-can-be]
summary: "The IR_WRITE/IR_WRITELN arms of the two ESP backends ask DIFFERENT questions. ir_codegen_xtensa.inc:3781 asks `TargetPlatform = PLATFORM_ESP`; ir_codegen_riscv32.inc:3569 asks `EspBareBoot`. On --esp-profile=bare they agree and the no-op is documented (docs/targets/esp32.md:70). ON THE IDF PROFILE THEY DO NOT AGREE AND NEITHER IS RIGHT: xtensa DROPS writeln silently (`--emit-obj --platform=esp` gives code=208948 for an empty program and for a writeln hello-world, byte-identical), while riscv32 EMITS it into the internal syscall write path (258,788 vs 258,828 — a 40-byte delta in code AND data; the object carries 32 `ecall`s against the bare object's 2, and `write` is NOT an external, only calloc and free are). So on a chip the xtensa build prints nothing and the riscv32 build traps to IDF's machine-mode handler. Nothing is documented as a no-op on the IDF profile — docs/targets/esp32.md scopes that note to the bare profile only. XTENSA IS THE PRIMARY ESP TARGET AND IS THE ONE THAT SILENTLY DROPS."
---

# The divergence

    ir_codegen_xtensa.inc:3781    if TargetPlatform = PLATFORM_ESP then   { no-op }
    ir_codegen_riscv32.inc:3569   if EspBareBoot then                     { no-op }

`DerivePlatform` (compiler.pas:243) reads
`if EspBareBoot or (TargetArch = TARGET_XTENSA) then TargetPlatform := PLATFORM_ESP`.
**For riscv32 the two spellings coincide** (bare -> ESP, else POSIX) — which is
exactly why copying one for the other looks safe. **For xtensa they do not**:
xtensa defaults to ESP, so an ordinary `--target=xtensa --platform=esp` IDF
build has `EspBareBoot` FALSE and `TargetPlatform` = PLATFORM_ESP.

# Measured 2026-09-18

| build | empty | hello | verdict |
| --- | --- | --- | --- |
| xtensa `--platform=esp --emit-obj` | `code=208948 data=3368` | `code=208948 data=3368` | **byte-identical — dropped** |
| riscv32 `--platform=esp --emit-obj` | `code=258788 data=4072` | `code=258828 data=4112` | **+40/+40 — emitted** |
| xtensa `--esp-profile=bare` | `code=46436` | `code=46436` | identical (documented) |
| riscv32 `--esp-profile=bare` | `code=57900` | `code=57900` | identical (documented) |

`riscv32-esp-elf-objdump -d` on the riscv32 IDF object: **32 `ecall`s**, against
2 in the bare object. `riscv32-esp-elf-nm -u` lists exactly `calloc` and `free`
— **`write` is not an external**, so the write path is internal and reaches the
kernel by `ecall`. On ESP-IDF that is not a Linux `write`; it traps.

# This axis already has a ruling, and it was applied to one subsystem only

`ir_codegen.inc:1374` settles it in its own words, for the SIGNAL runtime:

> *"BUT `not EspBareBoot` IS NOT THAT AXIS ON XTENSA, and the ruling's step 3 got
> this wrong by copying riscv32's spelling rather than its meaning. ... Gating on
> `not EspBareBoot` there would emit a Linux-syscall signal runtime for ESP-IDF
> and CALL its installer at startup. For riscv32 the two spellings coincide
> (bare -> ESP, else POSIX), which is exactly why copying the spelling looked
> safe. TargetPlatform is the axis; EspBareBoot is one input to it."*

**Nobody checked the WRITE path for the same pair of spellings.** That is
CLAUDE.md's own rule arriving in a second subsystem — *"grep for the OTHER
SPELLING'S HANDLER, not for the feature"* — and here the two spellings are in
two files that no grep for `writeln` brings together, because neither arm
contains the word.

# Which one is wrong

**Both.** The ruling says `TargetPlatform` is the axis, so riscv32's
`EspBareBoot` is the wrong QUESTION and its IDF builds emit a write path that
cannot work. But xtensa, asking the right question, still answers by **silently
discarding a statement the programmer wrote** — on a profile where a console
genuinely exists (IDF's own `esp_rom_printf` is named in
`docs/targets/esp32.md`'s Mode 2 section as an external the IDF link resolves).

So the fix is not "make riscv32 match xtensa". It is:

1. **Ask `TargetPlatform` in both** — one question, per the ruling.
2. **On the IDF profile, route write/writeln to `esp_rom_printf`** (or the PAL
   equivalent), which the IDF link already resolves. That is the arm that
   should exist and does not.
3. **Keep the bare no-op**, which is documented and correct, and now warns
   (`bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok`).

# Positive control for whoever takes it

Assert that an empty program and a `writeln` hello-world are **NOT** byte-
identical on any profile that claims to have a console, and **ARE** identical on
`--esp-profile=bare`. Both directions, because the first cut of the warning in
the sibling ticket fired on a program with no console output at all and that
only showed up against the empty-program row.
