# Retro / verdict — Antigravity asm-emitter trial (2026-06-14)

Trial of the scoped unban (see `antigravity-asm-emitter-task.md`,
`agents/AGENTS.md` access restrictions). **One agent: Antigravity.** It was given
the rv32 ticket, then permission to pick up the remaining emitter tickets too.
Not multiple agents — a single fast model that produced a lot of work in hours.

## What it delivered (functionally correct)

Four target asm text emitters — `EmitAsm386`, `EmitAsmRv32`, `EmitAsmA64`,
`EmitAsmArm32` — each:

- genuinely wired into its codegen (call sites: 386=4, rv32=4, a64=10, arm32=12),
- exercised by the passing QEMU suites (`test-i386` / `test-aarch64` /
  `test-arm32`, `test-emit-obj`),
- with a standalone byte test asserting against llvm-mc oracle bytes (386=17,
  rv32=12, a64=20, arm32=18 checks, 0 fail),
- `make bootstrap` stays byte-identical, `make test` green.

The compiler builds, self-compiles byte-identically, and runs correctly on every
target. The raw output is real and useful. Credit where due: fast, and it works.

## Where it fell down (structure + test hygiene — needs fixing)

It **ignored the design it was told to copy** (`asmtext_xtensa.inc` = one
per-platform file, the precedent in the brief) and produced the opposite:

1. **Monolith.** All four emitters dumped into `compiler/asmtext.inc`, bloating
   it from ~470 to **2834 lines** (~5x). The shared-core file is now a grab-bag.
2. **Duplication + dead files.** It *also* created per-platform files
   (`asmtext_rv32.inc`, `asmtext_a64.inc`, `asmtext_arm32.inc`), then
   copy-pasted each body into the monolith and wired the monolith. The
   standalone files are **not `{$include}`d** by `compiler.pas` — dead. Every
   rv32/a64/arm32 emitter exists **twice** (verified byte-for-byte identical, so
   pure duplication). No `asmtext_386.inc` at all.
3. **Tests validate the dead copies.** `test_asm_emit_{rv32,a64,arm32}.pas`
   `{$include}` the orphan files, **not** the `asmtext.inc` versions the compiler
   ships. They pass only because the copies still match — they give false
   confidence and will silently drift.
4. **Tests not wired into the build.** None of the four `test_asm_emit_*.pas` are
   in a `make` target → no regression guard; the "focused test" acceptance line
   was satisfied as a file, not as enforced CI.
5. **No `test-riscv32` target** → the rv32 emitter has no QEMU run-path coverage
   in the suite (weakest-validated of the four).
6. Left build artifacts (`test/*.o`) in the tree.

## Verdict

**Functional output: yes. Engineering discipline: no.** Antigravity is fast and
gets working code on the page, but it does not respect existing structure,
duplicates instead of factoring, and treats tests as a checkbox rather than a
guard. Net: useful as a raw-output generator under **tight structural
acceptance criteria and review**, not as an autonomous owner of design-sensitive
work. Functional acceptance gates were not enough — next time the gate must also
assert structure (file layout, no duplication, tests include shipped code, tests
wired into `make`).

**Decision (2026-06-14): re-banned.** The supervision + cleanup overhead cost
about as much as writing the emitters from scratch would have. The goal of this
project's agent setup is to amplify thoughts into code, not to babysit — a tool
that nets zero after its own mess fails that goal regardless of raw speed. The
structural acceptance criteria are preserved as the "Operating manual" in
`agents/AGENTS.md` (the bar it failed), not as an invitation to retry. Cleanup of
this trial's output is tracked in `chore-asmtext-per-platform-split` (done,
Claude-owned) — exactly the factoring discipline this trial showed it lacks.
