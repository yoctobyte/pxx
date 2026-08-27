---
slug: feature-a-wasm32-target-registration-skeleton
title: "Land the wasm32 target REGISTRATION on master before the wasm branch exists — 9 shared files, no codegen"
track: A
prio: 60
type: feature
blocked-by: []
status: done
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

- 2026-08-27 (frank-optimize) — **LANDED.** `TARGET_WASM32 = 6` registered
  across the shared files; no codegen, no encoder, no writer.

### What changed, and why each site

| file | what |
| --- | --- |
| `defs.inc` | the constant + `TargetArchName` -> `'wasm32'` |
| `compiler.pas` | `--target=wasm32` arm; `TARGET_PTR_SIZE := 4`; **explicit `Error` in the output-writer dispatch** (it fell through to `writeELF`, i.e. a 64-bit ELF for a 32-bit non-ELF target); a `--list-targets` row |
| `lexer.inc` | `CPU32` / `CPUWASM32` / `CPU_WASM32` defines + a loud `else` |
| `ir_codegen.inc` | **explicit `Error` in the backend dispatch** — it falls through to the x86-64 emitter, so without an arm wasm32 got x86-64 machine code in a file claiming to be wasm |
| `exception_emit.inc` | wasm32 arm + a loud `else` |
| `coroutine_emit.inc` | wasm32 arm (see the caveat below) |
| `emit.inc` | wasm32 joins the 4-byte-pointer fixup-width list |

`symtab.inc`, `elfwriter.inc` and the `pasparser_*` files needed **nothing**:
their target tests are ESP/riscv-specific (`iram`, `interrupt`, `Real = Single`,
bare-metal profile), and wasm32 correctly takes the not-ESP branch of each.
`elfwriter.inc:2335` already refuses `--emit-obj` for anything but
xtensa/riscv32, which covers wasm32 with a good message. That is why this came
in well under the ~270-line estimate: the estimate was measured from a commit
adding **two ESP targets**, and most of its width was ESP profile plumbing that
a wasm target does not have.

### The fail-open audit — the scan found 2 of 4

The ticket predicted the scan undercounts. It did, in both directions:
`exception_emit.inc:8` and `lexer.inc:936` are real (as filed);
`coroutine_emit.inc:25` is real but currently **unreachable**; and the scan
missed the two that matter most, because both are `if/Exit` ladders rather than
`if/else if` chains, so a heuristic looking for a missing `else` cannot see them:

- **`ir_codegen.inc:9048`** — `IREmitMachineCode`. Falls through to the x86-64
  emitter. A 7th target silently gets **x86-64 machine code**.
- **`compiler.pas:2082`** — the output writer. Falls through to `writeELF`.

Both are now loud. Worth carrying into
`refactor-a-target-dispatch-chains-fail-open`: **grep for `Exit`-terminated
target ladders, not just for chains missing an `else`.**

Two `else` arms were added (`lexer.inc`, `exception_emit.inc`) where all six
existing targets are already covered by explicit arms, so they are unreachable
today and exist for target #8. `coroutine_emit.inc` deliberately did **not**
get one: riscv32/xtensa fall through it silently on purpose ("later phases"),
and making them loud would move an existing target — that belongs to the
refactor ticket, not to a registration ticket bound by acceptance #3.

### Acceptance

1. **Clear error naming the facility, never a crash or a silent empty output.**
   `--target=wasm32 hello.pas` -> `error: wasm32: code generation not
   implemented`; a program with `try`/`raise` -> `error: wasm32: exception
   runtime not implemented (setjmp/longjmp has no wasm lowering — the module
   needs the exception-handling proposal or a trampoline)`.
   **Honest caveat:** the codegen arm fires first for most sources (the builtin
   heap's bodies compile before the later runtimes are emitted), so the
   **coroutine arm is currently unreachable and was NOT exercised** — it is a
   safety net that lights up as the wasm backend lands. The exception arm IS
   reachable and was exercised (the runtime is enabled during the parse).
2. **`make compiler/pascal26` converges byte-identical** — `converged after 1
   round(s)`, fixedpoint `a49d915e18f7`, confirmed different from `pinned`.
   `tools/gate.sh quick` GREEN (self-host fixedpoint + testmgr quick).
3. **No existing target moved — measured, not argued.** A fixed 8-program
   corpus (arrays, strings, records, constinit, hello, two exception units, and
   a try/except/finally program that exercises the exception runtime I touched)
   compiled for all six existing targets = 48 rows, hashed before and after:
   **48/48 identical**, failures included (the same 22 cross-target gaps fail
   identically). The "before" compiler was rebuilt from a stash of these edits
   and reproduced `591ae8160f69` exactly, so the oracle is the same binary the
   session started from rather than an approximation of it.
   *Method note:* the first corpus contained no `try` at all, so it did not
   cover the one chain where a bare `else` was added. That hole was found by
   checking coverage rather than by assuming it, and closed by adding `exc.pas`
   and re-running both sides.

`frankwasm` is unblocked: the wasm branch can now add only new files, and
touches no shared file until it emits.
- 2026-08-27 — resolved, commit PENDING-COMMIT.
