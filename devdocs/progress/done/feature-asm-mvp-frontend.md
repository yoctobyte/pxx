# MVP `.asm` -> executable path (head #3, fast-tracked ahead of #1/#2)

- **Type:** feature (frontend / linker) — Track A
- **Status:** urgent
- **Opened:** 2026-06-30
- **Relation:** the fast, minimal slice of head #3 in
  [[feature-assembler-first-class-citizen]] — full design/scope is
  [[feature-asm-source-frontend]] (`-c`/`ET_DYN`/full directive set, stays
  the reference for where this grows). This ticket exists to unblock Track B
  sooner, not to replace that one. Consumes
  [[feature-asmcore-encoder-library]] (Track B, `lib/asmcore`, in progress —
  x86-64 `mov reg,imm` / `add reg,reg` / `ret` landed so far).

## Why urgent, why now, why a cut-down scope

Track B is building `lib/asmcore` test-first, but today the only way to
verify it is a Pascal wrapper program that calls `AsmEncodeX64` directly and
byte-compares (`test/test_asmcore_x64.pas`) — workable, but not "trivial":
no way to just write a `.asm` fixture and run it like a normal test program.

**Asking for the minimal version, not the full one.** The full
[[feature-asm-source-frontend]] design (object/exe/`.so` output, full
directive set, the elegant global-symbol-resolution layer Track A wants to
build properly) is bigger than what's needed right now. What unblocks Track
B immediately is much smaller, and — usefully — needs **zero** of the
label/relocation "magic" ([[feature-asm-structured-ir-library]]) at all:
`lib/asmcore`'s current instruction set (`mov`, `add`, `ret`) has no
branches and no global references yet, so a frontend that only handles
**straight-line instruction sequences** is sufficient today and trivially
correct to scope.

## Goal (cut down from the full ticket)

`pxx foo.asm -> a.out` (`ET_EXEC` only — no `-c`, no `.so`, those stay in
[[feature-asm-source-frontend]]):

- Parse a flat sequence of instruction lines (mnemonic + operands, one per
  line, comments, blank lines) — **no labels, no `jmp`/`jcc`, no `extern`/
  `global`, no sections.** Reject (clear error) anything needing those; they
  come later via the full ticket once `lib/asmcore` actually has branches.
- Each line becomes a `TAsmInstr` ([[feature-asmcore-encoder-library]]'s
  type), encoded via `AsmEncodeX64` (or whatever target the test targets —
  x86-64 first, matching `lib/asmcore`'s current coverage).
- Blit the resulting bytes into a minimal `ET_EXEC` via the existing
  `elfwriter.inc` writer (already supports `ET_EXEC` — see audit in
  [[feature-asm-source-frontend]]). Entry point = first instruction; program
  must end in `ret`/`syscall exit` or similar — whatever's simplest, this is
  a test harness, not a general linker yet.

## Explicitly deferred to the full ticket

- Labels, branches, forward/backward jumps.
- `extern`/`global`, any cross-module symbol resolution.
- `-c` (object file) and `--shared` (`.so`, the confirmed `ET_DYN` gap).
- Multi-target — land x86-64 only for now; `lib/asmcore` doesn't have other
  targets yet either.

## Acceptance

- A hand-written `.asm` file using only `mov`/`add`/`ret` (matching
  `lib/asmcore`'s current coverage) assembles via `pxx` and runs, producing
  the expected result (e.g. an exit code or simple syscall side effect).
- Track B can write a `.asm` test fixture, run it through `pxx`, and check
  real program behavior — no more hand-deriving expected byte arrays for
  every new instruction `lib/asmcore` grows.
- Self-host byte-identical; doesn't touch anything outside this new minimal
  frontend path (no regressions to existing `.pas`/`.c` compilation).

## Log
- 2026-06-30 — Opened urgent (Track B, on behalf of Track A scope per repo
  convention — touches `compiler/**`/`elfwriter.inc`). User-requested
  fast-track: build the minimal #3 first so Track B's own testing has a
  trivial path, ahead of the full 3-head sequencing in
  [[feature-assembler-first-class-citizen]].

## DONE 2026-06-30 (self-host; FPC bootstrap deferred)

`pxx foo.asm -> ET_EXEC` shipped. compiler/asmfront.inc parses a flat
mov/add/ret sequence (comments, blank lines; rejects labels/jumps/extern/global/
sections/syscall with a clear error), encodes each line through lib/asmcore's
AsmEncodeX64 (asmcore compiled INTO the compiler via `uses asmcore_base,
asmcore_x64`), blits the bytes into Code[] (entry = first instruction), and
appends a fixed exit epilogue (`mov eax,60; syscall`) so the program exits with
whatever it left in rdi.

- Fixture test/test_asm_mvp.asm (`mov rdi,21; add rdi,rdi` -> exit 42), gated by
  `make test-asm` (in `make test`). Track B can now drop a `.asm` and run it.
- PXX self-host byte-identical; full `make test` green; libc-free output.
- lib/asmcore reached via a built-in unit-search dir (compiler.pas AddPasUnitDir)
  for self-host + `-Fulib/asmcore` in FPCFLAGS.

Deferred (filed): FPC bootstrap can't compile asmcore (no `{$mode objfpc}`) —
[[bug-asmcore-fpc-bootstrap]]; two name-resolution rough edges worked around —
[[bug-compiler-uses-unit-interactions]]. Full directive set / labels / objects /
.so stay in [[feature-asm-source-frontend]].
