---
slug: feature-target-wasm
title: "wasm32 as a target — 7th backend, WASI PAL, own branch and own gate"
track: A+B
prio: 60
type: feature
blocked-by: []
status: working
owner: frankwasm
created: 2026-08-27
summary: "NOT DISPATCHABLE — held by a standalone checkout on branch `wasm`. Emit wasm32 modules from the shared IR: new backend + module writer + WAT text emitter (Track A, new files), plus lib/rtl/platform/wasi (Track B). Two shared-file escapes: VMT slots hold code addresses (wasm has none — they become table indices) and exceptions are a hand-rolled setjmp/longjmp that does not port. Worked in a STANDALONE checkout (~/frankwasm) on branch `wasm`, self-gated, NOT swept by Track T. Do not claim."
---

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
