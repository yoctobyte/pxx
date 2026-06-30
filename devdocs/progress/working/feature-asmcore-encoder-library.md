# `lib/asmcore` — clean standalone multi-target instruction encoder library

- **Type:** feature (library) — Track B
- **Status:** working
- **Owner:** Track B (franktrackD)
- **Opened:** 2026-06-30
- **Relation:** layer 1 of [[feature-assembler-first-class-citizen]]'s
  2-layer architecture. Layer 2 (symbolic resolution: labels, frame slots,
  global relocations, plus migrating the compiler's own codegen onto this
  library) is Track A's job — see [[feature-asm-structured-ir-library]]. This
  ticket is pure mechanical encode/decode, no compiler-internal dependency.

## Why a separate library, not another `compiler/*enc.inc`

The compiler already has six ad hoc per-target encoders entangled with
codegen internals: `compiler/x64enc.inc`, `rv32enc.inc`, `xtensaenc.inc`
(typed binary encoders) and `asmtext.inc` / `asmtext_386.inc` /
`asmtext_a64.inc` / `asmtext_arm32.inc` / `asmtext_rv32.inc` /
`asmtext_xtensa.inc` (text-driven wrappers with inline label/relocation
bookkeeping bolted on). They work, but they're hard for a human to audit
against an ISA reference — encoding logic, label fixups, and relocation
plumbing are all mixed in the same functions, copy-pasted with variations
per target.

`lib/asmcore` is the clean rebuild: **given a mnemonic and already-resolved
operands (registers, immediates, raw byte/word offsets — no labels, no
symbol names, no frame slots), produce machine code bytes** — and the
inverse, a textual printer for the same instruction. No knowledge of
symbols, relocations, or the compiler's symbol table. That separation is
what makes it auditable: each instruction's encoding is one function,
testable in isolation against a known-good byte sequence (objdump/as output),
with nothing else going on.

## Goal

A library at `lib/asmcore/` covering, per target (x86-64 first, then i386,
aarch64, arm32, riscv32, xtensa — same six the compiler already backends):

- Instruction encode: `mnemonic + operands -> bytes`.
- Instruction text/disassemble: `bytes -> mnemonic + operands` (or at minimum
  `internal-instruction-record -> text`, full disassembly of arbitrary bytes
  is a stretch goal, not a requirement).
- Operand model: registers, immediates, memory `[base+disp]` / `[base+
  index*scale+disp]` where the target has it, and an opaque "patch this
  N-byte slot later" marker for anything that needs a value not known yet
  (no naming/lookup logic — keep it minimal). Track A owns the actual
  global-symbol resolution design (cross-module label lookup, link-time
  binding by name, all in-memory — no temp files/external `ld`) on top of
  this; don't gold-plate this side of the contract guessing what they'll
  want, a flat patch-site list is enough to build on.

## Explicitly out of scope (Track A's job, not this ticket)

- Label tables, forward-jump fixups, `@glob`/`@data`-style symbolic
  relocation — anything that needs to know about the compiler's symbol
  table or other instructions' positions. This library encodes one
  instruction at a time from fully-resolved inputs.
- Wiring into `compiler/asmenc.inc`, `elfwriter.inc`, or any `ir_codegen*.inc`
  backend. Track A does that once the library is solid (see
  [[feature-asm-structured-ir-library]]).

## Directory / dev-independence

Lives at `lib/asmcore/`, peer to `lib/rtl` / `lib/pcl` / `lib/crtl`. Stays
**independent during development** by construction: nothing in `compiler/**`
`uses`-es it yet, so it can't destabilize the compiler's self-host gate while
it's being built out. Tested standalone (`make lib-test`-style, own test
programs under `test/` exercising the library directly, asserting byte
output against known-good encodings).

**Write it as a normal, modern Pascal `unit`** — full language, not the
flat-`{$include}`/no-`+`-on-hot-path style `asmenc.inc`/`asmtext.inc` use.
That old style exists because *those specific files* are physically
`{$include}`-d into `compiler.pas`'s self-compilation closure. `lib/asmcore`
isn't, and doesn't need to be: `compiler/builtin/builtin.pas` is proof this
already works cleanly — it's a real `unit` (not an include), auto-pulled into
the compiler's own self-host build via the same general unit-loader that
already searches `compiler/`, `compiler/builtin/`, `lib/rtl/`, `lib/pcl/`, in
that order (`compiler/parser.inc` ~14042-14046). Promotion later is adding
`lib/asmcore/` to that same search list (or moving the proven code into
`lib/rtl`) — a small, low-risk change, not a structural unknown.

**Decided (2026-06-30): no classes.** Plain procedural units, matching
`builtin.pas` exactly — proven safe through the self-host fixedpoint gate,
whereas `class`/OOP self-hosting cleanly isn't demonstrated yet (`lib/rtl`'s
class-heavy units only ever compile for *user* programs via the stable
pinned `PXX_STABLE` binary, a different path than `compiler.pas` compiling
itself). No reason to take on an unproven risk here when procedural units
already do everything this library needs.

One per-target unit (`asmcore_x64.pas`, `asmcore_aarch64.pas`, …) mirroring
the existing `asmtext_<target>.inc` split, but as real units instead of
includes — this is exactly the kind of target-specific-behavior split
`.inc` was originally used for, done as units instead. Watch for circular
`uses` between them (shared operand-classification helpers belong in a
common `asmcore_base` unit each target unit depends on, not on each other) —
units have reference-ordering problems same as includes do, just shaped
differently; same care, not more.

## Scope / sequencing

All six targets are the goal (x86-64, i386, aarch64, arm32, riscv32, xtensa)
— not x86-64-only. Sequencing is about proving the *abstraction* is right
before fanning out wide, not about limiting ambition:

1. x86-64 core: the instruction set `compiler/x64enc.inc` +
   `compiler/asmtext.inc`/`asmenc.inc` already cover between them (ALU,
   shifts, unary, stack, setcc/cmovcc, zero-operand forms, `db/dw/dd/dq`) —
   match or exceed that coverage, cleanly.
2. One structurally different target next (e.g. aarch64 or riscv32 — fixed-
   width, load/store, no ModRM/SIB) to pressure-test that the operand model
   and patch-site abstraction generalize beyond x86's addressing modes, not
   just its register set. This is the real proof point, more than i386
   (which is mostly x86-64 with the lid off).
3. Once two structurally different targets share the same abstraction
   cleanly, the rest (i386, arm32, the remaining one of aarch64/riscv32,
   xtensa) is comparatively mechanical — same shape, new mnemonic tables.
4. Textual printer per target, designed in from the start (not bolted on
   later) — this is what makes [[feature-asm-textual-emit-mode]] and
   [[feature-asm-source-frontend]] cheap once Track A wires them up.

## Acceptance

- Each target's core instruction set encodes to byte-identical output vs. a
  known-good reference. Oracle choice (host `as`/`objdump`, hand-derived
  constants, or both) is a test-writing-time decision, not fixed here.
- Standalone test suite, runs without touching `compiler/**` or rebuilding
  the compiler (Track B gate — built with `$(PXX_STABLE)`, never rebuilds
  the compiler).
- Code is readable enough that a human can check one function against an ISA
  manual page without cross-referencing five other files (the explicit
  complaint about the current emitters this ticket exists to fix).

## Log
- 2026-06-30 — Opened (Track B). This is the actual legwork ticket for this
  session — pull into `working/` when starting implementation.
