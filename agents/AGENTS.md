# Agent notes (PXX / frankonpiler)

Shared instructions for any AI agent (Claude, Codex, agy, …) working this repo.
Read once at session start. Keep edits here terse — this loads every session.

## Navigation
- **Read `agents/codemap/symbols.md` before grepping the source.** It's a per-file index of every
  constant, type (with fields), global, and routine signature (with the
  doc-comment above each) with line numbers (the `.inc` files are huge).
  Regenerate after code changes: `make symbols` (`tools/gen_symbols.py`, stdlib
  only). Line numbers drift between regens — verify a line before editing.
- The `.inc` files are `{$include}`d into one unit: symbols share a single flat
  namespace (a name has one definition project-wide).
- Current work & design context lives in `docs/README.md`, `docs/project-state.md`,
  `docs/todo.md`, and active `docs/plan-*.md` files. Completed handovers are
  archived under `docs/historic/`.

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
- Attribution: if you add a `Co-Authored-By` trailer, use your own actual
  agent/model identity, never another agent's. Examples:
  `Co-Authored-By: Codex <codex@openai.com>`,
  `Co-Authored-By: Claude <claude@anthropic.com>`,
  `Co-Authored-By: Antigravity <antigravity@google.com>`.
- If continuing uncommitted work from an unknown/crashed agent, say so in the
  commit body (e.g. "Continues uncommitted changes present at session start;
  original agent unknown.") and list what you personally changed.
- Agents should keep agent-to-agent coordination notes under `agents/` when
  possible. Handovers are a good model: short, dated, attributable, and easy
  for the next agent to find without cluttering the repository root.

## Bug tracking (`docs/bugs/`)
- File-per-bug, **folder = status**: `discovered/` → `working/` → `fixed/`, plus
  `unfixed/` (parked/wontfix/can't-repro). `git mv` between folders is the only
  state change. Spec + file convention: `docs/bugs/README.md`.
- Found a bug mid-task: drop a `YYYY-MM-DD-slug.md` in `discovered/` and keep
  going; don't derail unless asked. On fix, add a `## Fix` section (commit +
  regression test) and `git mv` to `fixed/`.

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
