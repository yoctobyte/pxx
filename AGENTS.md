# Agent notes (PXX / frankonpiler)

Shared instructions for any AI agent (Claude, Codex, agy, …) working this repo.
Read once at session start. Keep edits here terse — this loads every session.

## Navigation
- **Read `codemap/symbols.md` before grepping the source.** It's a per-file index of every
  constant, type (with fields), global, and routine signature (with the
  doc-comment above each) with line numbers (the `.inc` files are huge).
  Regenerate after code changes: `make symbols` (`tools/gen_symbols.py`, stdlib
  only). Line numbers drift between regens — verify a line before editing.
- The `.inc` files are `{$include}`d into one unit: symbols share a single flat
  namespace (a name has one definition project-wide).
- Current work & design context live in `docs/handover-*.md`; index in
  `docs/README.md`.

## Build & verify (non-negotiable)
- This is a **self-hosting** compiler. Any change that alters emitted code must pass
  the byte-identical gate: `make bootstrap` (2-stage build==verify; iterate to
  fixedpoint if it diverges once), then `make test`, `make test-nilpy`,
  `make fpc-check` — all green, all byte-identical.
- Tooling/docs/test-only changes (no compiler source edit) skip the gate.
- After touching any hardcoded record layout constant (RecSize/RecFieldOffset),
  optionally FPC-reseed via `make bootstrap` if things don't work out.

## Workflow
- Work on `master` directly. Commit per logical unit (fine-grained history).
- **Never push without explicit user confirmation.**
- End commit messages with the project's Co-Authored-By trailer for your model.

## Landmines (cost real time)
- **Don't add fields to `TSymbol` / `TParam` / `TProc`.** Their byte layout is
  hardcoded (symtab.inc RecSize/RecFieldOffset) and the field pool (`MAX_UFIELD`)
  is sized tight for self-compilation — adding a field overflows it. Use parallel
  arrays keyed by index instead (e.g. `ProcRetPtrElemTk`, `SymDynDepth`).
- **Keep new hot-path lookups O(1).** A linear `FindCTag` once regressed the GTK
  parse to O(n²)/544s; it's hashed now (mirror `FindCTypedef`). Linear scans over
  per-symbol tables in a parse loop are the usual culprit.
- Never put a literal `{`/`}` inside a brace comment (nests, swallows code).

## Standing design laws
- **C imports are usable directly from every frontend; hand-written wrappers are
  optional, never required.**
- **Memory ownership: whoever reserves, frees.** Never free foreign memory; borrow
  by default; copy into our memory to keep (then we own/free the copy).
- No optimization passes by design (bootstrap-phase simplicity); the IR path is the
  default backend.
