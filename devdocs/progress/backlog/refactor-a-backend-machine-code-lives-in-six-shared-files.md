---
track: A
prio: 35
type: refactor
blocked-by: []
summary: "A backend is not ir_codegen_<arch>.inc + asmtext_<arch>.inc. Six shared files emit or name per-arch machine code: symtab.inc (three full function epilogues), asmenc.inc (inline-asm text for all five targets), ir_codegen.inc (the shared -O pipeline calls two aarch64 passes by name), asmfront.inc, exception_emit.inc, and -- the one that crosses a lane -- cparser.inc, the C FRONTEND, which writes the C _start entry stub as raw rv32_/a64_/arm32_ emission. Measured by the omission defines, which turn every one of these into a compile error."
---

# Backend machine code lives in six shared files, not two

## The measurement

Adding `PXX_NO_I386` / `PXX_NO_ARM32` / `PXX_NO_AARCH64`
([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]) forces
every cross-file reference into the open as an FPC "identifier not found". The
result is that omitting a backend requires guards in **six** shared files, not two:

| file | what it holds | why that is surprising |
| --- | --- | --- |
| `ir_codegen_<arch>.inc` | the backend | expected |
| `asmtext_<arch>.inc` | its text engine | expected |
| **`symtab.inc`** | three **full function epilogues emitting raw machine code** — i386 as inline `EmitB($0F); EmitB($B6); …` byte streams, arm32 143 lines, aarch64 173 lines, adjacent, each ending `Exit` | this is the *symbol table* |
| **`asmenc.inc`** | `Asm<arch>IsBranchOrJump` / `Asm<arch>AppendIdent` / `AsmParseBodyText<arch>` for **all five** targets | ~100 lines per arch of backend text handling |
| **`ir_codegen.inc`** | the shared `-O` pipeline calls `UnifiedResidencyAssignA64` and `FloatPoolBoundaryAssignA64` unconditionally | the shared optimizer knows one backend's pass names |
| **`exception_emit.inc`** | per-arch machine-code emission for the exception path — 91 riscv32 references, 45 xtensa, in 435 lines | same species as `symtab.inc`'s epilogues, found one increment later |
| **`cparser.inc`** | the **C frontend** writes the C `_start` entry stub as raw backend emission — `rv32_sw` / `rv32_lw` / `rv32_addi` / `EncodeRISCVJalr` at 8960-9015, with parallel arms at 8292 / 8416 / 8518 for the other targets; 185 raw-emit call sites in the file overall | a *frontend* holding machine code, and it is **Track C's file-lane, not A's** |

Plus the dispatch arms in `asmfront.inc` (four per target) and `compiler.pas`, which
are legitimate — a dispatcher naming its cases is the point of a dispatcher.

## The two found by the riscv32/xtensa increment (2026-08-19)

The first four came out of `PXX_NO_I386` / `PXX_NO_ARM32` / `PXX_NO_AARCH64`. Trialling
`PXX_NO_RISCV32` (518 errors) and `PXX_NO_XTENSA` (288; 805 for the pair) added two more,
and the second one changes the shape of this ticket rather than lengthening it:

`exception_emit.inc` is more of the same and is A's to fix. **`cparser.inc` is not.** A
frontend that emits machine code is the exact inversion of
[[the-substrate-is-ast-and-ir-not-the-parser]]'s rule — share the AST and the IR,
duplicate the parser — because here the *parser* is what got shared with the backend.
The C driver's entry stub is not a C-language concern; it is a target ABI concern that
happens to be reachable only from the C driver, the same way the signal runtime turned
out to be reachable only from the Pascal driver
([[bug-a-only-the-pascal-driver-emits-the-signal-runtime]]). Two frontends, two
driver-private pieces of target machinery, both invisible until a define removed the
target underneath them. That is the pattern, and it predicts a third.

The real fix is therefore narrower than "move backend code out of shared files": **the
per-target program-entry stubs belong in one place below the frontends**, next to
`EmitSignalRuntimeForTarget`, as an `EmitEntryStubForTarget`. That deletes the
cross-lane edit as a side effect — A stops needing to touch `cparser.inc` at all.

## Why this is worth a ticket rather than a shrug

**It contradicts the substrate note in the direction that costs most.**
`devdocs/dev/ir-as-substrate.md` says the shared middle is AST + IR and the
per-target part is the backend. The measurement says the per-target part *leaks up
into* the shared middle, and specifically into `symtab.inc`, which has no business
emitting instructions at all.

The concrete costs, in order of how likely they are to bite:

1. **A new target is a bigger job than it looks.** Someone adding one reads
   `ir_codegen_<arch>.inc` and `asmtext_<arch>.inc`, writes those two, and then finds
   the function epilogue is somewhere else entirely.
2. **A change to the epilogue contract must be made three times, by hand, in three
   adjacent blocks that do not share a line of code.** Exactly the shape
   `devdocs/dev/normalise-dont-special-case.md` warns about: the second and third
   arms are the ones that stay broken.
3. It is what makes each omission define a multi-file edit rather than deleting two
   `{$include}` lines.

## What NOT to do

**Do not chase this as a big move.** The guards landed already and the defines work;
nothing is blocked. The value is in the epilogues specifically — three
copies of one contract — not in relocating every `Asm<arch>` helper for tidiness.
`asmenc.inc` holding per-arch text routines is at least *cohesive* (they are all
inline-asm text handling, grouped by arch, contiguous, and now individually guarded).

The one that is plainly misplaced is `symtab.inc`'s three epilogues. Start there,
and only if a reason to touch them arrives independently.

## Provenance

Measured 2026-08-19 by frank3 while building the backend omission defines
(`91ca417b3`, `ccef81c7c`, `bde028cbe`). Not a bug — nothing is wrong today; this is
the coupling measurement the reduced-compiler ticket exists to take, written down so
it is not re-derived.
