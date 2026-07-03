# Assembler as a first-class citizen (umbrella)

- **Type:** feature (compiler architecture) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (user request: "proper assembler, on all targets")
- **Relation:** umbrella over [[feature-asmcore-encoder-library]] (Track B,
  layer 1), [[feature-asm-structured-ir-library]] (Track A, layer 2),
  [[feature-asm-textual-emit-mode]], [[feature-asm-source-frontend]]. Absorbs
  the goals of [[feature-inline-asm-depth]] and [[feature-inline-asm-multi-arch]]
  (both stay open as detailed scope/acceptance refs, not duplicated here).
- **Stale-ref note (2026-07-03):** layer 2 ([[feature-asm-structured-ir-library]],
  the ir_codegen→asmcore emitter migration) was REJECTED by user decision —
  see that ticket's log and [[feedback_no_emitter_migration_asmcore]]. Layer 1
  (asmcore) stays as the reused encoder library only; per-target emitter files
  (asmtext_*/x64enc/rv32enc/xtensaenc) stay put, not migrated.

## Sequencing update (2026-06-30): head #3 fast-tracked, urgent

User call: don't land heads in 1→2→3 order. Fast-track a **minimal** head #3
first — see urgent ticket [[feature-asm-mvp-frontend]] — so Track B has a
trivial `.asm`-file-in, run-it-and-check-behavior test path for
`lib/asmcore` as it grows, instead of only hand-derived byte-comparison
Pascal tests. That MVP deliberately needs none of layer 2's label/relocation
work (today's `lib/asmcore` coverage is straight-line `mov`/`add`/`ret`, no
branches yet) — it's a real shortcut, not a reordering for its own sake. The
full [[feature-asm-source-frontend]] (labels, `-c`, `.so`, multi-target)
still follows the layered plan below once layer 2 exists.

## Two-layer architecture (2026-06-30 — owner split)

The user drew an explicit line: the actual instruction-encoding tables are
**library legwork (Track B)**; the symbolic-resolution "magic" that makes
labels/globals/relocations work, plus migrating the compiler's own codegen
onto the result, is **Track A's** — it touches shared compiler internals
(`elfwriter.inc`, `ir_codegen*.inc`, the symbol table) and per the repo's
file-ownership rule that's not Track B's lane to implement, only to file.

- **Layer 1 — [[feature-asmcore-encoder-library]]** (Track B): a new,
  clean, standalone library at `lib/asmcore/`. Mechanical only —
  `mnemonic + resolved operands -> bytes` and the inverse text form. No
  symbol-table awareness, no relocations beyond an opaque "patch this slot
  later" marker. Lives outside `compiler/**` so it can be built and tested
  without touching the compiler's self-host gate, and stays uninvolved with
  the compiler until it's proven.
- **Layer 2 — [[feature-asm-structured-ir-library]]** (Track A): labels,
  frame-slot resolution, global/data relocations — the part that needs the
  compiler's symbol table and codegen-time fixup machinery
  (`elfwriter.inc`'s `EmitGlobRef`/GOT patching). Once `lib/asmcore` covers
  enough of an ISA, this layer is also where Track A **retires the legacy
  emitters** (`compiler/x64enc.inc`, `rv32enc.inc`, `xtensaenc.inc`,
  `asmtext*.inc`, `asmenc.inc`) by migrating `ir_codegen*.inc` and inline-asm
  parsing onto `lib/asmcore` — "current emitters are ugly and prone to
  errors / hard to validate by a human" is the explicit reason this
  migration is a goal, not just a nice-to-have.

Heads 2 and 3 below sit on top of layer 2 and inherit `lib/asmcore`'s
textual printer once it exists.

## Goal

Three user-facing heads, one underlying engine:

1. **Inline asm compiles through a real encoder** — `asm ... end` /
   `assembler` routines get labels, branches, global-var operands, explicit
   memory operands, and (eventually) every backend, not just x86-64.
2. **Codegen can emit assembly text instead of object bytes** — a debug/
   readability mode (`-S`-style flag). Accepted perf cost: compile time is
   dominated elsewhere, not in the emit step, so a textual pass is cheap
   insurance for readable codegen output and diffing across compiler changes.
3. **The compiler can assemble** — feed it a `.asm` file and get a valid
   object file (`.o`), executable (ELF), or shared library (`.so`) out, the
   same way `.c` is already a first-class frontend alongside `.pas`.

## Why these are one project, not three

`compiler/asmenc.inc` (x86-64 inline-asm encoder) already documents its own
ceiling in `devdocs/developer/inline-asm.md`: it encodes straight into a flat
byte buffer **at parse time**, with no symbolic/relocation layer. That's
exactly why labels, branches, and global-var operands don't work yet (TODO
#1-3 in that doc) — there's nowhere to hang a fixup.

A **structured, symbolic instruction-list IR** (mnemonic + operands + label
refs + global refs, encoded/resolved at codegen-or-link time through the same
relocation machinery `elfwriter.inc` already runs for normal Pascal codegen —
`EmitGlobRef`, GOT patching, etc.) fixes that ceiling once, and every head
consumes it:

- Head 1 (inline asm) parses into this IR instead of flat bytes →
  labels/globals/mem-operands fall out for free.
- Head 2 (textual emit) is a pretty-printer over the same IR the binary
  encoder already walks — one mnemonic table, two output backends (bytes,
  text), not two parallel implementations to keep in sync.
- Head 3 (`.asm` frontend) parses external assembly text into the *same* IR
  head 1 produces, then reuses `elfwriter.inc` (which already writes ET_REL
  objects and ET_EXEC executables — `ET_DYN`/`.so` output is a confirmed gap,
  see [[feature-asm-source-frontend]]) to link it.

Best validation of the whole stack: round-trip a program through head 2
(emit `.s` text) then head 3 (reassemble that text) and diff against direct
binary emission. Byte-identical output proves the textual form is faithful
and the assembler is real, not a toy.

## Per-target scope — corrected 2026-06-30

**All targets are in scope: x86-64, i386, aarch64, arm32, riscv32, xtensa.**
Initial research undersold this — turns out a label-aware, relocation-aware
text-to-binary engine (`compiler/asmtext.inc` + one `asmtext_<target>.inc`
each) **already exists for every one of the six targets**, used internally by
each `ir_codegen*.inc` backend as a readable alternative to hand-encoding.
See [[feature-asm-structured-ir-library]] for the full audit. This means:

- Head 1 (inline asm) multi-arch is mostly *wiring the parser to an existing
  per-target engine*, not building six new encoders — see corrected
  [[feature-inline-asm-multi-arch]].
- Head 2 (textual emit) coverage is already uneven-but-present per target —
  xtensa/arm32/aarch64/riscv32 lean on the text engine heavily already;
  x64/i386 mostly bypass it (older backends), so they're the long pole.
- Head 3 (`.asm` frontend) can target all six via the same existing engines
  as its backend; the frontend parser and the `ET_DYN`/`.so` writer gap are
  the genuinely new pieces, equally needed regardless of target.

Land x86-64 first end-to-end (richest existing groundwork, all three heads),
then the rollout to the other five is comparatively cheap per
[[feature-asm-structured-ir-library]]'s analysis.

## Acceptance (umbrella-level)

All three sub-tickets land; self-host stays byte-identical; `make test` +
cross green; at least one nontrivial test program round-trips head 2 → head 3
byte-identical on x86-64.

## Log
- 2026-06-30 — Opened (Track B, filing on behalf of Track A scope per repo
  convention — touches `compiler/**`/`elfwriter.inc`, not `lib/**`).
