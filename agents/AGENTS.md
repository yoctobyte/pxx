# Agent notes (PXX / frankonpiler)

Shared instructions for any AI agent (Claude, Codex, agy, …) working this repo.
Read once at session start. Keep edits here terse — this loads every session.

## Access restrictions
- Antigravity CLI is allowed again (unbanned 2026-06-14), but **scoped**. It may
  work only on a single, explicitly assigned per-target asm text-emitter ticket
  (`feature-i386-asm-emitter` / `feature-rv32-asm-emitter` /
  `feature-aarch64-asm-emitter` / `feature-arm32-asm-emitter`) — claim that one
  ticket, touch only the files its scope names, do not roam into other tickets or
  backends, and stop at the ticket's byte-identity acceptance gate. The earlier
  ban (2026-06-12) was a tooling-reliability issue: that run exhausted its tokens
  roaming across source files, leaving mixed unreviewed WIP that needed
  quarantine. The bounded scope + fixed encoding oracle (llvm-mc) are the
  guardrails for this trial. Not a judgment on the underlying model.
- Trial outcome (2026-06-14, see `agents/discussion/antigravity-asm-emitter-retro.md`):
  it delivered all four emitters **functionally correct** (QEMU green, bootstrap
  byte-identical) but with poor structure — a 5x monolith in `asmtext.inc` plus
  dead duplicate files, tests pointing at the dead copies, tests not wired into
  `make`. Verdict: fast, useful raw output, weak engineering discipline; keep it
  scoped + reviewed, and bake **structural** acceptance into the ticket (file
  layout, no duplication, tests include shipped code + wired into `make`) — not
  just functional gates. Cleanup tracked in `chore-asmtext-per-platform-split`
  (Claude-owned).

## Navigation
- **Read `agents/codemap/symbols.md` before grepping the source.** It's a per-file index of every
  constant, type (with fields), global, and routine signature (with the
  doc-comment above each) with line numbers (the `.inc` files are huge).
  Regenerate after code changes: `make symbols` (`tools/gen_symbols.py`, stdlib
  only). Line numbers drift between regens — verify a line before editing.
- The `.inc` files are `{$include}`d into one unit: symbols share a single flat
  namespace (a name has one definition project-wide).
- `docs/` is short **user** docs; **developer** docs live under `docs/developer/`
  (index: `docs/developer/README.md`). Current work & design context:
  `docs/developer/project-state.md`, `docs/developer/todo.md`, and active
  `docs/developer/plan-*.md`. Completed handovers archived under
  `docs/developer/historic/`.

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

## Progress tracker (`docs/progress/`)
- One board of tickets (bugs/features/tests/chores). **Status = folder**, **type
  = filename prefix** (`bug-`, `feature-`, `test-`, …). One ticket per `.md`,
  appendable `## Log`. `git mv` between folders is the only state change. Docs
  only → skip the self-host gate. Spec: `docs/progress/README.md`.
- Folders: `backlog/` (or `urgent/`) → `working/` → `done/`, plus `blocked/`
  (needs-user / can't-repro) and `rejected/`.
- **Claim before working:** `git mv` to `working/` and set `Owner` in the same
  commit (multi-agent: one file per ticket = few conflicts). New item mid-task:
  drop a `backlog/` ticket and keep going. On `done/`, append commit + test.
- **Priority = dependencies, not labels.** Tickets carry `Blocked-by:` /
  `Unblocks:` edges. A ticket is *ready* when its `Blocked-by` slugs are all in
  `done/`; *leverage* = how many tickets it unblocks. Pull high-leverage ready
  tickets (or by locality of what you're already editing). `urgent/` is a
  WIP-limited (~3) human override. Compute it: `tools/progress.sh`. When you spot
  "X before Y", add `Blocked-by` to Y — landing X makes Y ready automatically.
- After any board change, regenerate the committed snapshot:
  `tools/progress.sh board-md` (then commit `docs/progress/BOARD.md` with it).
  `tools/progress.sh check` fails on a stale board, dangling slugs, or cycles.
- Design + rationale (why folders/filenames/edges, tradeoffs, multi-agent
  semantics): `agents/progress-tracker-design.md`. Format spec:
  `docs/progress/README.md`.
- Record + state, not a clean DB — duplicate/stale tickets tolerated, prefer
  parking to losing info. No separate index; written status stays in
  `docs/developer/project-state.md` / `docs/developer/todo.md`.

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
