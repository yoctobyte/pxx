---
slug: feature-target-wasm
title: "wasm32 as a target — 7th backend, WASI PAL, own branch and own gate"
track: A+B
prio: 60
type: feature
blocked-by: [refactor-a-target-properties-have-no-single-answer]
status: blocked
owner: frankwasm
created: 2026-08-27
summary: "Emit wasm32 modules from the shared IR: new backend + module writer + WAT text emitter (Track A, new files), plus lib/rtl/platform/wasi (Track B). Two shared-file escapes: VMT slots hold code addresses (wasm has none — they become table indices) and exceptions are a hand-rolled setjmp/longjmp that does not port. Worked in a STANDALONE checkout (~/frankwasm) on branch `wasm`, self-gated, NOT swept by Track T. Do not claim."
---

# Do not claim this ticket

It is held by a dedicated standalone checkout (`~/frankwasm`) working on branch
`wasm`, with its own gate. This entry exists so the board reflects reality and
so the dependency on the helpers refactor is visible — not for dispatch.

The development plan is on that branch: `devdocs/dev/wasm/PLAN.md` and
`devdocs/dev/wasm/CHARTER.md`.

# Why it is blocked

`refactor-a-target-properties-have-no-single-answer` must land first. wasm32 is
a 32-bit-pointer target, and the 36 files that ask `TargetArch` in raw
`if`/`else if` chains with an implicit x86-64 fallthrough are exactly what gets
that silently wrong. Doing the helpers first makes this a refactor with a
byte-identical acceptance test; doing them after makes it remediation inside a
new backend.

**No wasm code is written until that ticket is green.**

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
- 2026-08-27 — filed from the scoping session; blocked on the helpers refactor
  by design. Findings: `devdocs/dev/wasm-target-findings.md`.
