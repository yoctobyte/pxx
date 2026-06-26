# Agent notes (PXX / frankonpiler)

Shared instructions for any AI agent (Claude, Codex, agy, …) working this repo.
Read once at session start. Keep edits here terse — this loads every session.

## Access restrictions
- **Antigravity CLI is not allowed on this repository** (re-banned 2026-06-14
  after a scoped trial). Do not claim tickets, edit files, or run tasks with it.
- Why, final: it was briefly unbanned for one scoped trial (the per-target asm
  emitters). It delivered all four **functionally correct** (QEMU green,
  bootstrap byte-identical) — fast — but with poor structure: a 5x monolith in
  `asmtext.inc`, dead duplicate files, tests pointing at the dead copies, no
  `make` wiring (see `agents/discussion/antigravity-asm-emitter-retro.md`). The
  cleanup (`chore-asmtext-per-platform-split`) cost about as much as writing the
  emitters from scratch. Decisive reason: Antigravity needs continuous
  babysitting, and **the goal here is to amplify thoughts into code, not to
  supervise an agent.** A tool that nets zero after its own cleanup overhead
  fails that goal. Re-banned — not a verdict on the raw model speed, a verdict
  on the supervision cost.
- The "Operating manual" below is kept as the **bar it failed** — the
  non-negotiable conditions that would be required if it is ever reconsidered.
  It did not meet them autonomously, and meeting them for it is the babysitting
  we are declining.

## Operating manual for Antigravity (currently banned — kept as the failed bar)

Antigravity is banned (see Access restrictions). This section is retained as the
conditions that would have to hold to reconsider it — it met none of them
autonomously. Distilled from the 2026-06-14 emitter trial. Antigravity writes
strong *local* code fast but has **no global stewardship**: it duplicates
instead of factoring, ignores existing structure and precedent, and treats tests
as a checkbox. The supervision needed to compensate is the babysitting this
project declines.

**Use it for:** mechanical, single-file, fully-specified work against a fixed
oracle — encode-this-ISA, convert-these-N-named-blocks, fill-a-mnemonic-table,
byte-for-byte ports. Also fine as a throwaway first draft you will refactor.

**Do NOT use it for:** file layout, where shared helpers live, cross-cutting
refactors, API/ABI design, or anything where "where does this go" is the hard
part. It will pick wrong and duplicate.

**Mandatory guardrails (put these in the ticket, not just in your head):**
1. **Pre-declare the file map.** Name every file it may create or touch, and say
   where each new symbol goes ("EmitAsmFoo → `asmtext_foo.inc`; shared helpers →
   `asmtext.inc`"). If it isn't named, it's off-limits. Stops the monolith.
2. **One ticket = one unit = its named files.** Hard file-count ceiling. Scope is
   the leash — it roams without one.
3. **Structural acceptance criteria, not just functional.** Spell out, as
   pass/fail: exactly one definition per symbol (`grep -c`), no un-`{$include}`d
   new file, no copy-pasted block (factor shared code), tests `{$include}` the
   *shipped* file (never a copy), tests wired into `make`. Functional gates
   (QEMU green, bootstrap byte-identical) passed last time while structure rotted
   — they are necessary, not sufficient.
4. **Give the precedent explicitly AND a grep gate.** It had `asmtext_xtensa.inc`
   as the model and ignored it. A precedent alone does not bind it; pair it with
   rule 3.
5. **Never self-mark done. Human/Claude review gate first.** A `grep` for dup
   defs + a quick structure diff (2 min) catches its failure mode. No commit to
   `done/` without that pass.

If a task can't be reduced to rules 1–3, don't give it to Antigravity — do it
with a model that can own structure.

## Navigation
- **Read `agents/codemap/symbols.md` before grepping the source.** It's a per-file index of every
  constant, type (with fields), global, and routine signature (with the
  doc-comment above each) with line numbers (the `.inc` files are huge).
  Regenerate after code changes: `make symbols` (`tools/gen_symbols.py`, stdlib
  only). Line numbers drift between regens — verify a line before editing.
- The `.inc` files are `{$include}`d into one unit: symbols share a single flat
  namespace (a name has one definition project-wide).
- `docs/` is short **user** docs; **developer** docs live under `devdocs/developer/`
  (index: `devdocs/developer/README.md`). Current work & design context:
  `devdocs/developer/project-state.md`, `devdocs/developer/todo.md`, and active
  `devdocs/developer/plan-*.md`. Completed handovers archived under
  `devdocs/developer/historic/`.

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

## Progress tracker (`devdocs/progress/`)
- One board of tickets (bugs/features/tests/chores). **Status = folder**, **type
  = filename prefix** (`bug-`, `feature-`, `test-`, …). One ticket per `.md`,
  appendable `## Log`. `git mv` between folders is the only state change. Docs
  only → skip the self-host gate. Spec: `devdocs/progress/README.md`.
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
  `tools/progress.sh board-md` (then commit `devdocs/progress/BOARD.md` with it).
  `tools/progress.sh check` fails on a stale board, dangling slugs, or cycles.
- Design + rationale (why folders/filenames/edges, tradeoffs, multi-agent
  semantics): `agents/progress-tracker-design.md`. Format spec:
  `devdocs/progress/README.md`.
- Record + state, not a clean DB — duplicate/stale tickets tolerated, prefer
  parking to losing info. No separate index; written status stays in
  `devdocs/developer/project-state.md` / `devdocs/developer/todo.md`.

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
