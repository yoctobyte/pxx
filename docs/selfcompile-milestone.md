# IR-to-IR Self-Recompile Fixedpoint

**Date:** 2026-05-28

Pascal26 achieved full IR-to-IR self-recompile fixedpoint today.

## What this means

A compiler that can compile itself is notable. A compiler that compiles itself using its own **experimental IR backend** — producing a byte-identical binary across three generations — is a different milestone entirely.

```
FPC
 └─▶ pascal26 (stage0, FPC-compiled)
       └─▶ /tmp/pascal26-build  (gen1, IR-compiled)
             └─▶ /tmp/pascal26-verify  (gen2, IR-compiled by IR-compiled)
                   └─▶ cmp: identical
```

No delta between gen1 and gen2. The IR backend is now self-consistent enough to compile itself correctly.

## What was broken

Two bugs, found in sequence:

### 1. `ResolveNodeRec` missing `AN_FIELD` case in `AN_INDEX`

`ResolveNodeRec` resolves an AST node to its record type — used by the IR
lowering pass to compute field offsets. For `AN_INDEX` nodes it only handled
the case where the base is `AN_IDENT` (e.g. `Syms[i]`). When the base was
`AN_FIELD` (e.g. `Procs[i].Params[j]`), it returned `REC_NONE`.

`RecFieldOffset(REC_NONE, anything)` returns 0 — so every field of `TParam`
mapped to offset 0. All reads and writes to `TypeKind`, `SymIdx`, `IsRef`,
`IsArray`, and `Name` aliased the same byte. The last writer in
`RegisterProc` was the `SymIdx` assignment, which left the symbol table
index in that slot.

When `MatchProcCall` later read `Params[j].TypeKind`, it got the symbol
index (473, 474, ...) instead of the type kind (1 = `tyInteger`,
4 = `tyString`). Every proc call type-check failed.

Fix: one `else if` branch — when `AN_INDEX` base is `AN_FIELD`, delegate to
`ResolveNodeRec(ASTLeft[node])`, which already returns the element record
type via `RecFieldRecId`.

### 2. `MAX_AST` / `MAX_TOKENS` too small for grown source

The compiler source grew past 131072 AST nodes after exception handling was
added. Formerly a global cumulative counter, this hit the ceiling before
the source finished compiling.

Fix part A: doubled `MAX_TOKENS` to 262144 (token array is pre-tokenized
for the whole source at once — a true global limit).

Fix part B: reset `ASTNodeCount := 0` after each `CompileAST` call. The
AST is fully consumed at that point; nodes from one function body do not
need to survive into the next. `MAX_AST` is now a per-function cap, not a
per-compilation cap, and 131072 nodes per function is not a realistic
constraint on any codebase.

## Who built this

This milestone was reached collaboratively. The IR backend, exception
handling, ABI implementation, and self-hosting infrastructure were built
across multiple sessions with several AI coding assistants:

- **OpenAI Codex** — contributed significant IR and codegen work
- **Google Gemini** — contributed significant IR and codegen work  
- **Anthropic Claude** (this session) — diagnosed and fixed the
  `ResolveNodeRec` bug that was blocking fixedpoint

The human author (yoctobyte) designed the architecture, directed the work,
and maintained the stable binary chain throughout.

## Why it matters

This is not a toy. `pascal26` is a real Pascal compiler targeting x86-64
Linux ELF, with a hand-written lexer, parser, symtab, native x86-64
codegen, an experimental IR backend, exception handling, generics,
operator overloading, classes, and a C preprocessor. Its source is ~440KB
of Pascal across ~13800 lines.

Achieving fixedpoint through the IR backend means the IR-generated code is
correct enough to regenerate itself exactly. The compiler now has two
independent paths to produce the same binary: the legacy direct codegen and
the IR backend.
