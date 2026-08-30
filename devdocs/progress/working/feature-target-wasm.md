---
slug: feature-target-wasm
title: "wasm32 as a target — 7th backend, WASI PAL, own branch and own gate"
track: A+B
prio: 60
type: feature
blocked-by: [decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal]
status: working
owner: frankwasm
created: 2026-08-27
summary: "NOT DISPATCHABLE — held by a standalone checkout on branch `wasm`. Emit wasm32 modules from the shared IR: new backend + module writer + WAT text emitter (Track A, new files), plus lib/rtl/platform/wasi (Track B). Two shared-file escapes: VMT slots hold code addresses (wasm has none — they become table indices) and exceptions are a hand-rolled setjmp/longjmp that does not port. Worked in a STANDALONE checkout (~/frankwasm) on branch `wasm`, self-gated, NOT swept by Track T. Do not claim."
---

> **DANGLING SHAS BY DESIGN.** Every commit sha in this ticket is on branch
> **`wasm`**, never on `origin/master`. This lane works in a standalone
> checkout and pushes to its own branch, so `progress.sh check`'s
> `SIDE-BRANCH-SHA` flag is correct rather than a defect. **Branch permission
> is not merge permission**: nothing on `origin/wasm` is pre-approved for
> master. Binary fingerprints (`fb83a9c891b9`, `5dcc99ff8725`) are sha256
> prefixes of `compiler/pascal26`, not commits at all.
> — frankwasm, 2026-08-30

# STATE, 2026-08-30 (supersedes the park record below)

**Held and active.** Branch `wasm` at **`cf75b5ce5`**, binary at self-host
fixedpoint **`5dcc99ff8725`** (sha256 of `compiler/pascal26`, verified not
inferred). Tree clean, everything pushed, all 30 `test/wasm` checks green.

Four phases landed since the park record below was written — 9j argv, 9k
`Frac`/`Int`, 9l `Write`/`WriteLn` of a real — so **that record is history, not
status.**

## Is the `blocked-by:` edge load-bearing? Yes, but only for the MILESTONE

Worth stating precisely, because a stale edge on a visibly-progressing ticket
misreports in both directions.

- **The anchor IS blocked.** All **32 of 32** remaining `compiler.pas`
  refusals are one shape — 17× `-50`, 8× `-100` (`LoadFile`), 6× `-52`, 1×
  `IR op 54` — every one file/directory/environment I/O, every one gated by
  `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`.
  There is no route to *pascal26 runs under wasmtime* that does not go through
  that answer.
- **The LANE is not blocked**, and that is measured rather than asserted.
  Compiling `lib_classes.pas` and `lib_variants_surface.pas` for wasm32 shows
  the non-anchor gaps: `IR_CLASSREF` (op 39, 8 bodies — the largest single
  item), `IR_VAR_STORE` (op 43), `IR_SET_LIT` (op 33), and a set-typed
  parameter (`TReplaceFlags`) that `WasmParamValType` has no answer for. Only
  `IR_SYSCALL` (op 54) among them is the U family.

So: keep the edge — it is a fact about the milestone — and read it as *the
milestone waits*, never as *the agent waits*. The lane has named, measured work
that the decision does not touch, and is doing it.

# PARKED 2026-08-30, UNPARKED same day — Phase 9j is in progress again

*(The park below stood for as long as it took the coordinator to point out that
"parked for want of a session" is a park with no owner and no expiry, written by
the session. Kept rather than deleted: it is an accurate record of the state, and
of the one defect this campaign has been filing all night applied to itself.)*

# What unparks it, and who owns that

Moved out of `working/` by its own holder: the lock means *an agent is actively
on it*, and nobody is. Tree clean, everything pushed, branch `wasm` at
`b564c8f39`, binary at self-host fixedpoint **`fb83a9c891b9`** (verified by
sha256 of `compiler/pascal26`, not inferred).

| what | blocked? | owner |
| --- | --- | --- |
| **Phase 9j — argv (`ParamCount`/`ParamStr`)** | **no — unblocked lane work** | this lane |
| Phase 7 — exceptions | no | this lane |
| **the Phase 9 anchor's last mile** (36 of 36 remaining refusals) | **yes** — `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`, now carried as this ticket's `blocked-by` edge | Track U |

**So this is NOT parked waiting for the decision.** argv is unblocked and fully
scoped; it is parked for want of a session, not a prerequisite. Whoever resumes
starts at PLAN.md's Phase 9j: a backend-emitted `WasmHostImport` pair
(`args_sizes_get` / `args_get`) plus one synthesised strlen, doing the managed
and frozen destinations in the same slice — and NOT taking the recorded
`argv[i+1] - argv[i] - 1` shortcut, which every host satisfies and preview1
does not specify.

**Provenance note for anyone measuring here.** Every number in PLAN.md Phases
9b-9j came from a binary this checkout self-hosted, named by sha; this lane has
never measured against `stable_linux_amd64/default/pinned`, so the 2026-08-30
pin churn (v394 blessed, reverted, re-blessed) does not touch any of them.

# Do not claim this ticket

It is held by a dedicated standalone checkout (`~/frankwasm`) working on branch
`wasm`, with its own gate. This entry exists so the board reflects reality and
so the dependency on the helpers refactor is visible — not for dispatch.

The development plan is on that branch: `devdocs/dev/wasm/PLAN.md` and
`devdocs/dev/wasm/CHARTER.md`.

# Not blocked (corrected 2026-08-27)

An earlier draft blocked this on a target-property refactor. That was wrong:
`TARGET_PTR_SIZE` already exists (`defs.inc:1758`, 129 call sites), and a wasm32
target declares its pointer width exactly where every other target does — the
`compiler.pas:1508` arm. There is no prerequisite.

What remains is a real but non-blocking hazard, filed separately as
`refactor-a-target-dispatch-chains-fail-open` (prio 50): several per-target
chains have no final `else`, so a 7th target matches no arm and is configured
as nothing, silently (`lexer.inc:936` is the worked example). Worth fixing on
the way past; not a gate in front.

# Scope

Measured accounting — op-by-op, PAL entry-by-entry, and sizing anchored to
comparable files in-tree — is in **`devdocs/dev/wasm-target-findings.md`** on
`dev`. Summary:

- ~50 of 76 IR ops transliterate mechanically (wasm locals = infinite typed
  register file; the riscv32 backend is the closest model).
- 5 control-flow ops restructure onto a `br_table` dispatch loop.
- 5 code-address ops become table indices + `call_indirect` — **shared-file
  change**, `elfwriter.inc:1926` / `emit.inc:105`.
- 7 exception ops get redesigned; `exception_emit.inc`'s setjmp/longjmp has no
  wasm equivalent. v1 route is pending-flag threading, which composes with the
  dispatch loop.
- 9 ops are already refused on non-x86 targets — free.
- PAL: ~35 of ~90 entries work under WASI preview1, ~55 refuse (all sockets, all
  process control, perms, mmap, dlopen, cwd). Same deliberate-refusal pattern as
  Track S's ESP backend, inverted: ESP has sockets and no files, WASI has files
  and no sockets.

Anchor milestone: **`pascal26` itself running under wasmtime**, with its emitted
output bytes identical to the native compiler's for the same input. It is the
one large program that fits the platform (single-threaded, file I/O only, no
sockets, no fork), and it is absolutely checkable.

# Lane and gate

- Track **A** file-ownership for `compiler/**` (all new files but the two
  escapes above), Track **B** for `lib/rtl/platform/wasi/**`.
- **Self-gated.** This branch does not rely on Track T and is not swept by it.
  Its gate is defined in `devdocs/dev/wasm/CHARTER.md` on the `wasm` branch.
- Merges `dev` in regularly; merges back only in green, reviewed units.

# Open questions to settle before the backend starts

- Does anything in the RTL rely on `IR_PROCADDR` values being **comparable** or
  arithmetic-able rather than merely callable? Table indices break both.
- Proposal baseline. Recommended: MVP + sign-ext + mutable-globals +
  bulk-memory + multi-value (all universally shipped since ~2021), memory32,
  **no** EH proposal for v1.
- WASI preview1 only. Browser is a second import profile, not WASI.

## Log
- 2026-08-27 — filed from the scoping session. Re-filed onto `master` after
  frank1-80 pointed out `dev` was retired on 2026-08-26 (collapse `8b2a6bae6`)
  and the original landed on a branch 379 commits behind. Unblocked in the same
  pass: the prerequisite was based on a wrong premise.
  Findings: `devdocs/dev/wasm-target-findings.md`.

## Phase 2 scaffolding: `unreachable` bodies, and the condition for removing it

Recorded here 2026-08-28 rather than only in the file that carries it, because a
scaffold whose retirement condition lives only where the scaffold lives is how
temporary things become permanent — the person who would remove it is the person
who stopped reading that file.

**What it is.** In `compiler/ir_codegen_wasm32.inc`, a body the backend cannot
yet lower is emitted as a single `unreachable` instead of aborting the compile,
and is recorded. `WasmReportCoverage` prints unconditionally before the module is
written:

```
wasm32: 5 of 125 bodies lowered; 120 emitted as `unreachable` (Phase 2 is incomplete):
    PXXHdrInit — non-i32 parameter base
    ...
```

**Why it exists.** Discovered by running, not by planning: even a trivial `.pas`
pulls `compiler/builtin/builtinheap.pas`, whose bodies use `IR_STORE_MEM`, calls
and control flow. The backend's first ever run stopped there, not in the test
program, and `-dPXX_NODEFAULTRTL` does not suppress it. Without the scaffold,
*nothing* is verifiable until most of Phases 2-4 exists at once.

**Why it is safe.** It reports itself unconditionally, so a module with trapping
holes can never be mistaken for a complete one; and an unlowered body traps
loudly at run time rather than computing quietly, which is the failure direction
this lane cares about.

**REMOVAL CONDITION — the reason this paragraph is on the ticket.** The scaffold
comes out when the coverage line reads `N of N`, i.e. `WasmBrokenCount = 0` for
the builtin set plus a real program. At that point `WasmUnsupported`,
`WasmReportCoverage`, `WasmBodyBroken` and the `unreachable` fallback are all
inert and should be deleted, and an unlowerable op should go back to being a
hard `Error`. **If this ticket closes with that code still present, the scaffold
outlived its purpose and the close is wrong.**

## Phase boundaries are now expressed in the coverage counter

`PLAN.md`'s original Phase 2 milestone — *"a program with arithmetic, records and
arrays, no control flow, produces the same value as its native build"* — is
**known-unreachable** and has been rewritten. It assumed a program could be
compiled in isolation. It cannot: the builtins come too, and they need control
flow and calls. The replacement milestones are stated as properties of the
coverage report, because `5 of 125` is a real metric and "Phase 2 complete" is
not. See `devdocs/dev/wasm/PLAN.md` on the branch.


## Parked 2026-08-28 — moved out of `working/` by the coordinator

frankwasm sent an explicit park line at 19:26: tree clean, everything pushed, binary at the
committed fixedpoint `045366904b67`. `working/` is a **live lock**, so a ticket left there by a
parked session reads as "someone is on it" while nothing is happening — the same signature this
campaign has been filing all day. Moved here rather than waking a parked session for a file
move; **nothing in the body was edited**, and frankwasm re-claims it from `unfinished/` on
resume.

**Where it stopped:** open-array parameters is banked *with a diagnosis, not started*. The
refusal's stated reason is stale (the dyn-array layout it names landed in Phase 9a) but its
verdict is correct, and the one-liner that reading invites was measured wrong — it compiles,
reports `124 of 124 bodies lowered`, then traps with `memory access out of bounds`. Next session
starts at `IRLowerCallArg`'s argument paths, not at the parameter. Entangled with
`Length of Pointer`: every probe refused on `Length`/`High` before reaching the parameter, so
the two classes cannot be tested apart.

Session result: compiler.pas for wasm32 **56% → 97.6%** of bodies; 52 GB-and-never-finishing →
595 MB / 26.5 s. Nothing on `origin/wasm` is pre-approved by any of it — the five-arm, two-lane
merge ledger is unchanged.

## 2026-08-30 — the `blocked-by` edge, and why this ticket stops advertising itself

`blocked-by:` was `[]` until today. It is now the wasi-intrinsics decision, and
the change is a **measurement, not a judgment**: at
`compiler.pas` 3719 of 3755 bodies lowered, **36 of the 36 remaining refusals**
are that one decision — 35 in the builtins block (`writeELF*`, `writeU8/16/32/64`,
`LoadFile`) and the 36th `IR_SYSCALL`, which is the same question wearing a
different hat. There is no refusal left this lane can act on unilaterally.

That dependency was real for two days before this line existed. It was stated in
PROSE, in `devdocs/dev/wasm/PLAN.md`, **on a side branch** — invisible to the
ranker, invisible to `progress.sh check`, and invisible to anyone who has not
checked this branch out. The charter's own standing rule says anything other
agents must act on goes on `master` immediately; a `blocked-by` edge is exactly
that, and it took a re-measure of somebody else's stale blocker to notice this
lane had the same defect in a worse place.

**Two consequences, stated so neither reads as a surprise later.**

1. **This ticket drops out of `ready` while the decision is open, and that is
   accurate** — the remaining work genuinely is blocked. It is NOT abandonment
   and NOT a re-prioritisation: `prio: 60` is unchanged and the ticket keeps its
   owner and its `working/` lock. The lane still has unblocked work in front of
   it (Phase 9j's argv, Phase 7's exceptions); what is blocked is the *last mile*
   of the Phase 9 anchor.
2. **The decision's own priority now follows the ranker's rule instead of a
   human overriding it.** Effective prio propagates down `blocked-by` edges, so
   the decide inherits from what it unblocks rather than sitting at its filed
   `prio: 40` while gating a p60 anchor. Nobody edited that number and nobody
   should: the number is the U lane's call, the *edge* is a fact.
