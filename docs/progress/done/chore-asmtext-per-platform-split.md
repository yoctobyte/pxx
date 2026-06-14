# Split `asmtext.inc` monolith into per-platform files + fix emitter tests

- **Type:** chore
- **Status:** done
- **Owner:** Claude
- **Opened:** 2026-06-14

## Why

The Antigravity asm-emitter trial (see
`agents/discussion/antigravity-asm-emitter-retro.md`) landed four working
emitters but with bad structure: all four bodies were dumped into
`compiler/asmtext.inc` (~470 → 2834 lines) **and** duplicated into standalone
`asmtext_{rv32,a64,arm32}.inc` files that are not `{$include}`d (dead). Every
rv32/a64/arm32 emitter exists twice, byte-identical. The functional work is
correct (QEMU suites green, bootstrap byte-identical); this is purely the
structure/test-hygiene cleanup.

**Design intent:** one per-platform file per target, mirroring the existing
`asmtext_xtensa.inc`. `asmtext.inc` is the **shared core only** (the `AsmText*`
helpers, label/fixup table shape). Move code **into** the per-platform files —
do not grow the monolith.

## Target layout

```
compiler/asmtext.inc         shared core: AsmTextCharAt/slice/parse, hole
                             binding, label+fixup table shape. (EmitAsmX64 may
                             stay here as the reference impl, or move to
                             asmtext_x64.inc later — low priority.)
compiler/asmtext_386.inc     EmitAsm386      (NEW — no orphan exists yet)
compiler/asmtext_rv32.inc    EmitAsmRv32     (canonicalise the existing file)
compiler/asmtext_a64.inc     EmitAsmA64      (canonicalise)
compiler/asmtext_arm32.inc   EmitAsmArm32    (canonicalise)
compiler/asmtext_xtensa.inc  EmitAsmXtensa   (already correct — the precedent)
```

`compiler/compiler.pas` `{$include}`s `asmtext.inc` (core) first, then each
per-platform file.

## Source-of-truth rule (important)

The **shipped, known-good** code is the version inlined in `asmtext.inc` — that
is what passes QEMU + bootstrap. The orphan files are verified byte-identical
**today** but are not the source of truth. Canonicalise by extracting from
`asmtext.inc` (or diff orphan vs inlined first; if identical, just delete the
inlined copy and include the orphan). Do not blindly trust the orphans.

## Steps

1. For rv32/a64/arm32: confirm orphan body == inlined body (diff). If identical,
   delete the inlined copy from `asmtext.inc` and `{$include}` the file. If they
   differ, the inlined version wins — overwrite the file from it.
2. Create `asmtext_386.inc`, move `EmitAsm386` (+ overload) out of `asmtext.inc`
   into it.
3. Add the four `{$include}` lines to `compiler.pas` after `asmtext.inc`; verify
   include order (core helpers must precede the per-platform files).
4. Repoint each `test/test_asm_emit_{386,rv32,a64,arm32}.pas` to `{$include}`
   the **same** per-platform file the compiler ships (386 test → new
   `asmtext_386.inc`). Test must validate shipped code, not a copy.
5. Wire the four host byte tests into the Makefile — a `test-asm-emit` target
   (fpc-build + run each, like the existing x64 `test_asm_emit` at Makefile:221)
   and add it to the `test` aggregate.
6. Add a `test-riscv32` make target (QEMU run-path parity, mirror `test-arm32`)
   so the rv32 emitter gets run-path coverage.
7. `.gitignore` the `test/test_asm_emit_*` binaries / `.o`.

## Acceptance

- `asmtext.inc` back to shared-core size; **no duplicate emitter definitions**
  anywhere (grep each `EmitAsm*` → one definition).
- `compiler.pas` includes one per-platform file per target; build clean.
- Each `test_asm_emit_*.pas` includes the shipped per-platform file.
- `make test-asm-emit` runs all four and is part of `make test`; `test-riscv32`
  exists and is green.
- `make bootstrap` byte-identical; `make test` + `test-i386`/`test-aarch64`/
  `test-arm32`/`test-riscv32`/`test-emit-obj` all green.

## Log

- 2026-06-14 — opened from the Antigravity asm-emitter trial retro. Functional
  output correct; this tracks the structural + test-wiring debt it left.
- 2026-06-14 — done. Commits `e9c69f1` (split) + `a3376f7` (tests/make).
  - `asmtext.inc` back to 500 lines (shared core + EmitAsmX64). `EmitAsm386`
    moved to new `asmtext_386.inc`; rv32/a64/arm32 emitters now live in their
    (verified byte-identical) per-platform files, duplicates deleted from the
    monolith. `compiler.pas` includes one file per target.
  - `AsmRv32Trim` / `AsmRv32IsLabel` were generic helpers every target reused
    under an rv32 name → promoted to core as `AsmTextTrim` / `AsmTextIsLabel`,
    all callers repointed. One definition per `EmitAsm*` now (verified by grep).
  - Tests repointed to `{$include}` the shipped per-platform files (the 386 test
    had hand-copied the whole emitter inline — a third copy — now removed).
    Wired into a new `make test-asm-emit` target, added to `make test`
    (386=17, rv32=12, a64=20, arm32=18 byte checks, 0 fail). `test/*.o` ignored.
  - **Deviation:** no `test-riscv32` run target. The riscv32 Linux userland path
    is still a stub (hello.pas emits 8 bytes, no writeln; QEMU hangs), so there
    is nothing to run. The rv32 emitter is covered by the host byte test +
    `test-emit-obj`. A real `test-riscv32` waits on riscv32 Linux codegen
    (separate work, not part of this cleanup).
  - Verified: `make bootstrap` byte-identical; `make test` (incl test-asm-emit) +
    `test-i386` / `test-aarch64` / `test-arm32` / `test-emit-obj` all green.
