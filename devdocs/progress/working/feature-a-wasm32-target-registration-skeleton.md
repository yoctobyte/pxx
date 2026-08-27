---
slug: feature-a-wasm32-target-registration-skeleton
title: "Land the wasm32 target REGISTRATION on master before the wasm branch exists — 9 shared files, no codegen"
track: A
prio: 60
type: feature
blocked-by: []
status: working
owner: frank-optimize
created: 2026-08-27
unblocks: feature-target-wasm
summary: "Register TARGET_WASM32 across the 9 shared files a new target touches — constant, --target= arm, TARGET_PTR_SIZE := 4, and an explicit Error('wasm32: not implemented') in every dispatch chain — with NO codegen. Measured from bd49a5953, the commit that added riscv32+xtensa: ~270 lines over 9 shared files. Landing it FIRST means the wasm branch adds only new files and never merges a shared file until Phase 4. Also closes the practical half of refactor-a-target-dispatch-chains-fail-open."
---

# The point: move the conflict, don't manage it

`feature-target-wasm` is worked on a side branch precisely because it is ~85%
new files. The remaining 15% is what makes merges painful — and almost all of it
is not *codegen*, it is **registration**: teaching the existing dispatch chains
that a 7th target exists.

If registration lands on `master` **before** the branch accumulates work, the
branch touches **zero shared files** until Phase 4. If it lands later, every
`master` merge into the branch is a conflict in the files that change most.

This ticket is the cheap half, and it is worth doing on a day when nobody is
writing wasm code.

# Measured surface — from the last time a target was added

`bd49a59535c3` ("feat: stage-1 codegen for esp32 bare targets (riscv32 +
xtensa)") added **two** targets at once and touched:

| file | lines | what it is |
| --- | --- | --- |
| `symtab.inc` | 97 | layout / sizes |
| `parser.inc` (now the `pasparser_*` set) | 70 | target-conditional parsing |
| `emit.inc` | 34 | emission plumbing |
| `compiler.pas` | 20 | `--target=` arm, `TARGET_PTR_SIZE` |
| `lexer.inc` | 18 | CPU defines |
| `elfwriter.inc` | 12 | writer dispatch |
| `ir_codegen.inc` | 10 | backend dispatch |
| `exception_emit.inc` | 7 | exception runtime arm |
| `defs.inc` | 2 | the `TARGET_*` constant |

Plus the new files (`ir_codegen_riscv32.inc`, `rv32enc.inc`, and xtensa's pair),
which are not this ticket.

**~270 lines across 9 shared files, for two targets.** One target is less.

Today, 19 files mention `TARGET_RISCV32`; the 9 above are where a target is
*introduced*, the rest accreted later.

# Scope — registration only, and it must ERROR

- `TARGET_WASM32 = 6` in `defs.inc`.
- `--target=wasm32` in `compiler.pas`, setting `TARGET_PTR_SIZE := 4` in the
  existing `compiler.pas:1508` arm (wasm32 is a 32-bit-pointer target).
- In **every** dispatch chain that must know the target: an explicit
  `Error('wasm32: <this facility> not implemented')`.

**Nothing may silently no-op.** That is the entire value of the ticket, and it
is not hypothetical — two chains do exactly that today (see below).

Explicitly OUT of scope: any codegen, any encoder, any module writer, any PAL.
`--target=wasm32` should compile nothing and say so clearly.

# Two chains that would fail silently, measured

A heuristic scan of `master@f7671a8d5` for `TargetArch` chains of >=3 arms with
no final bare `else`:

```
  6 arms  compiler/exception_emit.inc:8
  4 arms  compiler/coroutine_emit.inc:25
```

Both would emit **nothing at all** for a 7th target — no exception runtime, no
coroutine runtime, no diagnostic. And `lexer.inc:936` is a third, found by hand
(it sits inside an outer `if TargetArch <> TARGET_X86_64` guard, which the scan
did not follow): wasm32 would get **no CPU defines at all**.

**The scan undercounts — it found 2 of at least 3.** Treat the audit as the work
and the scan as a starting point, not an inventory.

# Relationship to `refactor-a-target-dispatch-chains-fail-open`

That ticket is the general cleanup: give exhaustive-by-intent chains a mandatory
`else` so the *next* target is loud. This ticket is the same medicine applied to
one concrete target, and doing it necessarily fixes the chains wasm32 reaches.

Sensible order: **this one first** (it has a consumer and a deadline), then the
general sweep with the site list this one produces. Doing the general sweep
first is fine too; doing both independently is the only bad option.

# Acceptance

1. `pxx --target=wasm32 hello.pas` fails with a clear "not implemented" message
   naming the facility — never a crash, never a silently empty output.
2. `make compiler/pascal26` converges byte-identical.
3. **A fixed corpus compiled for all six existing targets is byte-identical
   before and after.** Registration must not move any existing target.

## Log
- 2026-08-27 — filed while scoping `feature-target-wasm`, deliberately ahead of
  any wasm code, to keep the branch free of shared-file merges.
  Findings: `devdocs/dev/wasm-target-findings.md`.
