# Split `asmtext.inc` monolith into per-platform files + fix emitter tests

- **Type:** chore
- **Status:** backlog
- **Owner:** Claude (recommended — structural factoring; see retro)
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
