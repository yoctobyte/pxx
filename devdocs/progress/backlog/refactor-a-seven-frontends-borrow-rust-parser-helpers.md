---
track: A
prio: 40
type: refactor
blocked-by: []
summary: "Zig, ALGOL, Erlang, Fortran, LOLCODE and Whitespace all call five helpers whose bodies live in rparser.inc, so PXX_NO_RUST alone fails with 198 errors and Rust can only be omitted together with all six. Three different layers are marooned under one R prefix: AST constructors (share, wrong file), RWiden (numeric widening — SEMANTICS, should not be shared at all), and REmitParamRegSpill (raw x86-64 emission in a frontend)."
---

# Seven frontends borrow rparser.inc's helpers

## The measurement (2026-08-19)

`-dPXX_NO_RUST` alone: **198 errors**, none of them Rust's. With Zig also
omitted: 74. With Zig and the six esoteric probes omitted: **0**.

| symbol | callers outside rparser | what it actually is |
| --- | --- | --- |
| `RMakeIdent` (72 refs) | zparser, gparser, eparser, fparser, lparser | `AllocNode(AN_IDENT)` — an **AST constructor** |
| `RSeqAppend` (65) | same | AST statement-list append |
| `RBinOp` (42) | same | `AllocNode(AN_BINOP)` |
| `RStoredName` (10) | zparser (9), eparser (1) | token-char-buffer interning |
| `RWiden` (7) | zparser (3), fparser, lparser, gparser (2 each) | **numeric widening — language semantics** |
| `REmitParamRegSpill` (1) | zparser | emits **raw x86-64** (REX bytes) |

Rust was the first skeleton written, so the ones after it reached for what was
there. The `R` prefix then hid what had happened: it reads as "Rust's", so nobody
asked whether an ALGOL parser should be calling it.

## Three layers, three different right answers

This is why the fix is not "move the R functions to a shared file".

1. **`RMakeIdent` / `RSeqAppend` / `RBinOp` — share, and they already are.**
   Per [[the-substrate-is-ast-and-ir-not-the-parser]] the AST *is* the shared
   substrate; these are AST constructors and sharing them is correct. The bug is
   only the file and the prefix. Move to a shared `astbuild.inc`, drop the `R`.

2. **`RStoredName` — share, but it lies in the error path.** Its overflow message
   reads `'Rust: token char buffer overflow'`. An Erlang or Zig program that
   overflows the buffer is told it is Rust. Move and reword.

3. **`RWiden` — do NOT share.** This is `a numeric widening rule`, i.e. a piece of
   one language's specification, and the same doc says duplicate semantics across
   languages because "a shared parser helper couples two specs and is wrong in
   both." The concrete case: **Zig has no implicit numeric widening at all** — it
   requires explicit casts — yet `zparser.inc` calls Rust's widening in three
   places. Whether those three sites sit on a path where it is observable is a
   Track Z question and is NOT asserted here; what is asserted is that the
   coupling exists and is the wrong shape. Each frontend should own its widening.

4. **`REmitParamRegSpill` — does not belong in a frontend at all.** Raw x86-64
   register-spill emission, called from Zig's parser. Same species as
   `cparser.inc`'s `_start` stub
   ([[refactor-a-backend-machine-code-lives-in-six-shared-files]]) and as the
   Pascal-only signal runtime
   ([[bug-a-only-the-pascal-driver-emits-the-signal-runtime]]) — **three
   frontends now, each holding a private piece of target machinery**. That is no
   longer a coincidence; it is the missing layer between the frontends and the
   backends showing up once per frontend.

## Consequence today

`PXX_NO_RUST` ships, but it is only usable together with `PXX_NO_ZIG` and the six
probe defines — documented in the feature ticket rather than enforced, because an
implicit "this define turns on those six" would hide exactly the coupling this
ticket exists to remove. Doing 1-3 makes `PXX_NO_RUST` stand alone.
