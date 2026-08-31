---
slug: feature-a-merge-the-wasm-branch-the-shared-file-arms
title: "Merge the wasm branch: the ledger of shared-file arms it carries, and the two lanes' gates that apply"
track: A
prio: 20
type: feature
blocked-by: []
status: open
owner: unassigned
created: 2026-08-28
summary: "Branch `wasm` modifies four existing files: compiler.pas (5 edits), exception_emit.inc (1 arm), ir_codegen.inc (1 arm), and lib/rtl/platform.pas (1 additive constant). The last is Track B and carries B's gate, so the merge review spans two lanes, not one. Nothing on the branch is pre-approved. This ticket is the ledger; the branch's own CHARTER table is not visible from master and was stale."
---

> **Re-priced by the owner, 2026-08-30: WASM IS LOW PRIO FROM NOW ON.** *"it works,
> it tests our IR, we should be able to compile applications.. for now, that's good
> enough."* The anchor is met — `pascal26` runs under wasmtime and emits an ELF
> byte-identical to the native compiler's for the same source. wasm has served its
> real purpose, which was exercising the IR from a second direction. These tickets
> stay OPEN and correct; they simply must not outrank ordinary Track A work. Pick
> them up on request, or when a lane is warm on the files anyway.

# Why this ticket exists

The `wasm` branch's strategy is *move the conflict, don't manage it*: it adds
new files and touches shared ones only under a named grant. That worked, and the
grants were real. What did not work is the **accounting**.

On 2026-08-28 the lane reported its merge set as four arms and omitted
`compiler/compiler.pas` entirely. The coordinator caught it by diffing the
branch instead of reading the summary. The lane's source for that summary was
the escapes table in `devdocs/dev/wasm/CHARTER.md`, which had not been updated
since Phase 1 — it still described the exception mechanism as "not yet taken"
three phases after it was taken.

**A ledger that lives on the branch is not a ledger.** It is invisible to
`master`, to `tools/progress.sh`, and to whoever reviews the merge — the same
defect `test/wasm/check_tickets.sh` was written to make unrepresentable for
tickets, recurring one level up for the record of what was granted. See
`feature-a-wasm32-compile-check-the-phase-2-backend`, filed the same day for a
grant whose only record was a branch commit message.

So this ticket is the ledger, on master, ranked. It is the merge itself, and it
carries the list the merge has to review.

# The arms, measured — `git diff origin/master...wasm`

| file | edits | what | grant / ticket |
| --- | --- | --- | --- |
| `compiler/compiler.pas` | 5 | 3 `{$include}` (`wasmenc`, `asmtext_wasm`, `ir_codegen_wasm32`); a forward for `IRTopLevelStmt` in the shared forward block; the `TARGET_WASM32` output arm `Error(...)` → `writeWasm(outFile)` | 3 by `feature-a-wasm32-module-writer-wiring`, 2 by `feature-a-wasm32-compile-check-the-phase-2-backend` |
| `compiler/exception_emit.inc` | 1 arm | the `TARGET_WASM32` arm: `Error(...)` → three poison values (`ExcSetJmpAddr`/`ExcLongJmpAddr`/`ExcRaiseAddr` := -1). Taken twice historically — the message text at Phase 1, the mechanism at Phase 7 | message text by `feature-a-wasm32-module-writer-wiring`; **the mechanism has no ticket** |
| `compiler/ir_codegen.inc` | 1 arm | the `TARGET_WASM32` dispatch arm: `Error(...)` → `IREmitMachineCodeWasm32; Exit;` | **no ticket** |
| `compiler/symtab.inc` | 1 arm + 1 comment | `EmitZeroFrameSlot`: an explicit `TARGET_WASM32` **no-op** arm at the top, plus a comment naming the chain's unnamed final arm as x86-64 rather than a default. Emits nothing for any other target | `bug-a-emitzeroframeslot-has-no-wasm32-arm` [A p55] |
| `compiler/ir_codegen.inc` | +1 arm | `EmitManagedLocalCleanupForTarget`: an explicit `TARGET_WASM32` no-op arm. That chain already fell through to nothing for wasm32, so this changes no bytes on any target and only names what was unnamed | same ticket |
| `lib/rtl/platform.pas` | 1 | `PAL_PLATFORM_WASI = 3` beside POSIX=1 and ESP_IDF=2. Additive; no existing line touched | **no ticket — and this one is Track B** |

New files are additive and collision-free and need no arm treatment:
`compiler/ir_codegen_wasm32.inc`, `compiler/wasmenc.inc`,
`compiler/asmtext_wasm.inc`, `lib/rtl/platform/wasi/platform_backend.pas`,
`devdocs/dev/wasm/**`, `test/wasm/**`.

# The merge spans TWO lanes' gates

This is the part that is easy to miss, because the branch has been an A-lane
effort since Phase 1 and the set was classified uniformly.

- `compiler/**` is **Track A**: `make test` + self-host fixedpoint
  (byte-identical), plus cross where a backend is touched.
- `lib/rtl/**` is **Track B**: `make lib-test` / `make demos`, built against
  `$(PXX_STABLE)`, **never rebuilding the compiler**.

`lib/rtl/platform.pas` and everything under `lib/rtl/platform/wasi/` are B's
files and carry B's gate. A reviewer running only A's gate has not reviewed
them. Track B is parked and does not know this branch exists; the constant alone
is not worth waking it for, but a merge is.

# What the arms are NOT

Three of the four are the same shape: a `TARGET_WASM32` arm that said `Error`
being replaced by the thing it was a placeholder for. The registration skeleton
put those `Error`s there deliberately, because the dispatch chains **fall
through** — a 7th target without an arm gets x86-64 machine code in a file
claiming to be its own. Two properties a reviewer should check rather than
assume:

- In `ir_codegen.inc` the `Exit` is now **load-bearing** rather than implied.
  An `Error` never returned; a call does.
- In `exception_emit.inc` the values are `-1` and not `CodeLen`. Nothing can
  reach them on this target, so the useful failure is a poison that reads as
  obviously wrong, not a trap. The xtensa arm four lines above is the opposite
  case and correctly differs.

# Standing constraint

**Nothing on the branch is pre-approved.** The grants above were for the
specific edits named in them; "covered by a prior ticket" and "not a shared-file
change" are different claims, and only the first is ever true of these. The
merge is a deliberate event proposed to the user, never automatic
(`devdocs/dev/wasm/CHARTER.md`, merge policy).

# Definition of done

The branch is merged, or the ledger is superseded by whatever replaces it. Until
then this ticket is the answer to "what shared files does `wasm` touch", and any
new arm the lane takes is added here **as it is taken**, on master, not at merge
time — which is the whole lesson of the two accounting failures above.
