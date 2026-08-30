---
slug: feature-target-wasm
title: "wasm32 as a target — 7th backend, WASI PAL, own branch and own gate"
track: A+B
prio: 25
type: feature
blocked-by: [decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal]
status: unfinished
owner: frankwasm
created: 2026-08-27
summary: "NOT DISPATCHABLE — held by a standalone checkout on branch `wasm`. Emit wasm32 modules from the shared IR: new backend + module writer + WAT text emitter (Track A, new files), plus lib/rtl/platform/wasi (Track B). Two shared-file escapes: VMT slots hold code addresses (wasm has none — they become table indices) and exceptions are a hand-rolled setjmp/longjmp that does not port. Worked in a STANDALONE checkout (~/frankwasm) on branch `wasm`, self-gated, NOT swept by Track T. Do not claim."
---

> **Re-priced by the owner, 2026-08-30: WASM IS LOW PRIO FROM NOW ON.** *"it works,
> it tests our IR, we should be able to compile applications.. for now, that's good
> enough."* The anchor is met — `pascal26` runs under wasmtime and emits an ELF
> byte-identical to the native compiler's for the same source. wasm has served its
> real purpose, which was exercising the IR from a second direction. These tickets
> stay OPEN and correct; they simply must not outrank ordinary Track A work. Pick
> them up on request, or when a lane is warm on the files anyway.

# PARKED 2026-08-30 — owner asked for less parallel work; wasm named explicitly

**Not blocked, not failing, not abandoned.** The owner asked for fewer lanes
running at once and named wasm as one to pause. Everything is committed and
pushed; the lane stopped mid-queue with work available, not stuck.

## State you can verify without asking anyone

| | |
| --- | --- |
| branch | **`wasm`** (`origin/wasm`), at **`f97477cf9`** |
| checkout | **standalone** (`~/frankwasm`), **self-gated, NOT swept by Track T** |
| divergence | **94 commits on `wasm` that are not on `origin/master`** |
| binary | self-host fixedpoint **`12bd7e665b5e`** — a **binary sha256** prefix of `compiler/pascal26`, NOT a commit |
| tests | **all 31 `test/wasm` checks pass** at that sha |
| tree | clean, nothing unpushed |

**Branch permission is not merge permission.** Nothing on `origin/wasm` is
pre-approved for `master`; 94 commits is a conversation with the owner, not a
merge anyone here can authorise.

## Resume here — four of the five need no decision

Measured, not guessed: compiling `test/lib_classes.pas` and
`test/lib_variants_surface.pas` for wasm32 and reading the refusal report.

| # | item | size | needs the U decision? |
| --- | --- | --- | --- |
| 1 | ~~`IR_CLASSREF` (op 39) — `is`/`as`, class refs, `ClassType`~~ | ~~8 bodies~~ | **DONE, Phase 9m** |
| 2 | `IR_VAR_STORE` (op 43) — store into a variant | 2 bodies | no |
| 3 | `IR_SET_LIT` (op 33) — set literal materialised to memory | 1 body | no |
| 4 | set-typed PARAMETER — `TReplaceFlags` on `StringReplace` / `TStringHelper.Replace`; `WasmParamValType` has no answer for a 32-byte set passed by value | 2 sites | no |
| 5 | `IR_SYSCALL` (op 54) | 1 body | **YES — this one only** |

Row 1 landed after this park was requested and before the lane stopped, so
**start at row 2.** `IR_VAR_STORE` pairs with the *write of a variant* refusal
already sitting in the same `WasmEmitWrite` arm (*"needs the slot ADDRESS, not
its value"*) — same shape, and a variant already lives in a slot, so it wants
`WasmLValueAddr` rather than the shadow-stack spill Phase 9l used for floats.

## Before you rebase from master: run forwardlint, and a red seed may not be yours

`python3 tools/forwardlint.py` — about a second, and it is what proves the FPC
BOOTSTRAP SEED still builds. Run it after any rebase from master, and before
each `make compiler/pascal26` while working.

**This is a coverage hole, not a discipline rule.** `make compiler/pascal26` is
the mandatory per-fix gate and it *cannot* catch a use-before-declaration, by
construction: pxx resolves across the unit and FPC resolves in source order, so
the file self-hosts green and only the seed fails. `gate.sh quick` does run
forwardlint (step 2, `fpc seed compiles (forward decls)`, `tools/gate.sh:216`) —
but `gate.sh quick` is OPTIONAL per fix and the loop that is mandatory does not
include it. So the check lives in the gate you may skip and is absent from the
one you may not.

**And the seed on `origin/master` was RED when this was parked**
(`pasparser_generic.inc:844` and `:1022`, another lane's, already routed). If
you rebase and the seed goes red, **check whether it is yours before assuming
it is** — five instances across four lanes on 2026-08-30 alone, every one with
the documented loop followed correctly, and at least one agent nearly spent a
session proving a break was not its own. This branch was green at
`f97477cf9`; forwardlint answers the question in a second.

## The one sentence a future reader most needs

**All 32 of 32 remaining `compiler.pas` refusals are a single shape.** The
histogram is 17× `-50`, 8× `-100` (`LoadFile`), 6× `-52`, 1× `IR op 54`
(`getdents64`) — every one file / directory / environment I/O, every one gated
by
[`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`](../backlog/decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal.md)
[U p70]. There is **no route to the anchor milestone** (`pascal26` running under
wasmtime) that avoids that answer, and answering it clears all thirty-two at
once.

**So read the `blocked-by:` edge as *the milestone waits*, never *the agent
waits*.** The edge is kept deliberately — removing it would misreport the anchor
as reachable, which is the worse error — but nothing was ever stalled behind it.
Rows 2-4 above are startable the moment someone resumes, with no decision
needed.

## Where the detail lives

`devdocs/dev/wasm/PLAN.md` **on branch `wasm`**, not on master. Phases 9j
(argv), 9k (`Frac`/`Int`), 9l (`Write` of a real) and 9m (`IR_CLASSREF`) all
landed on 2026-08-30 and each carries its own costing, its rejected
alternatives and what its test is shaped to catch.

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

## 2026-08-30 (frankwasm) — the whole wasm test lane is unreachable from any runner

Found from the outside, while draining `chore-a-sweep-the-unwired-tests-into-the-suite`,
and it is one line to fix if the answer is "a make target".

`test/wasm/` holds **37 `*_slice.pas` subjects and 38 `check_*.sh` scripts**, one
per slice, plus `check_all.sh` and `wat_oracle.sh`. The chain is complete and
correct: `check_all.sh` -> `check_<name>.sh` -> `<name>_slice.pas` (spot-checked:
`check_set.sh` names `set_slice.pas` three times).

**Nothing invokes the top of it.** `test/wasm` appears nowhere in the Makefile,
nowhere in `tools/`, nowhere in `testmgr.py`. Grepped every `.py`, `.sh` and the
Makefile outside that directory — the only hit is `test/wasm/proto/gen_exc_wat.py`,
i.e. the directory referencing itself. **The lane runs when a human types it and
at no other time.**

`check_test_wiring.py` has been reporting the 37 leaves as orphans, which is true
and has the wrong coordinates: wiring 37 slices individually would duplicate a
harness that is better than a rule per file. frankT has taken "this directory is
unreachable" as a real gap in that checker.

### Why this is worth a paragraph and not a line

`check_all.sh` exists **because this lane already lost a suite to exactly this
class of problem**. Its own header:

> *"a suite went red and stayed red across a handoff that reported it green...
> green looked like the ABSENCE of output. That is indistinguishable from a
> script that died at line 1, which is exactly what had happened."*

The fix was a positive sentinel per check — `PASS <name>`, unreachable under
`set -e`. Correct, and **one level short**: a sentinel proves the check ran *when
someone runs the check*. The same reasoning applied one level up asks who runs
`check_all.sh`, and nobody does.

### Three answers, and the resumer should pick deliberately

1. **A make target** invoking `check_all.sh` — one line, but it puts a wasm
   runtime on the critical path of whatever tier it lands in, and this box may
   not have one. Check before choosing.
2. **Deliberately hand-run**, with 37 `test/UNWIRED.txt` entries naming the
   harness as the reason. Honest, and stops the checker reporting it forever.
3. **Gated on runtime availability** — a target that skips loudly when no
   runtime is present. Note the skip must be LOUD: a silent skip is the same
   failure the sentinel was added to prevent, and this lane has already paid for
   that lesson once.

Nothing here is claimed or changed; the campaign stays parked. Recorded so the
resumer does not rediscover it, and so `check_test_wiring.py`'s 37 lines are not
read as 37 pieces of work.
