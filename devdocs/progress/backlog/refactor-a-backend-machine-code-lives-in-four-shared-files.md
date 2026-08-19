---
track: A
prio: 35
type: refactor
blocked-by: []
summary: "A backend is not ir_codegen_<arch>.inc + asmtext_<arch>.inc. symtab.inc carries three full function epilogues emitting raw machine code (i386 inline byte streams, arm32 143 lines, aarch64 173 lines) side by side; asmenc.inc carries the inline-asm text routines for all five targets; ir_codegen.inc's shared -O pipeline calls two aarch64 passes by name. Measured by the omission defines, which turn every one of these into a compile error."
---

# Backend machine code lives in four shared files, not two

## The measurement

Adding `PXX_NO_I386` / `PXX_NO_ARM32` / `PXX_NO_AARCH64`
([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]) forces
every cross-file reference into the open as an FPC "identifier not found". The
result is that omitting a backend requires guards in **four** shared files, not two:

| file | what it holds | why that is surprising |
| --- | --- | --- |
| `ir_codegen_<arch>.inc` | the backend | expected |
| `asmtext_<arch>.inc` | its text engine | expected |
| **`symtab.inc`** | three **full function epilogues emitting raw machine code** — i386 as inline `EmitB($0F); EmitB($B6); …` byte streams, arm32 143 lines, aarch64 173 lines, adjacent, each ending `Exit` | this is the *symbol table* |
| **`asmenc.inc`** | `Asm<arch>IsBranchOrJump` / `Asm<arch>AppendIdent` / `AsmParseBodyText<arch>` for **all five** targets | ~100 lines per arch of backend text handling |
| **`ir_codegen.inc`** | the shared `-O` pipeline calls `UnifiedResidencyAssignA64` and `FloatPoolBoundaryAssignA64` unconditionally | the shared optimizer knows one backend's pass names |

Plus the dispatch arms in `asmfront.inc` (four per target) and `compiler.pas`, which
are legitimate — a dispatcher naming its cases is the point of a dispatcher.

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
