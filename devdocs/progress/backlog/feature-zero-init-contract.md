# Zero-init contract — one library-owned managed-slot zeroing guarantee

- **Type:** feature (refactor / hardening)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16
- **Priority:** prerequisite before more cross-target codegen (see Why now)

## Problem — the seam

The "managed slots must be nil before first use" invariant is currently
**reimplemented inline, per emit-path, per target**, instead of living in one
owned place. Two shapes of the same bug keep biting:

1. **`not 15` → 14** (FIXED 606abec) — symptom of codegen making an assumption
   that didn't hold. Same *class* as below: behaviour split across sites.
2. **Stale non-nil'd slot → `DecRef` faults on a garbage handle.** A managed
   local (AnsiString / dyn-array / record-with-managed-fields / variant) whose
   slot was not zeroed before the body runs. First `SetLength` / assignment /
   ARC-correct whole-record copy reads stale stack bytes as a live handle and
   release/retain dereferences garbage. Surfaced as e.g. the arm32 startup
   segfault — which is **not** in the Int64 work that exposed it; it is
   pre-existing missing zero-init.

The invariant lives **half in codegen, half in `builtinheap.pas`**, and neither
side owns it fully:

- `parser.inc` ~6794–6888 zeroes managed *local slots* on frame entry with a
  per-target ladder (x86-64 `rep stosb` / qword mov; i386/arm32/aarch64 each
  their own; xtensa/riscv stubbed; "managed aggregate locals not yet supported"
  on the rest). Every target reimplements the same guarantee.
- `builtinheap.pas` GetMem zeroes the **free-list reuse path** (~119) but the
  **bump path** (~141) assumes a fresh mmap page is already zero. Correct today,
  but the split is a latent trap: any future bump-path change (reuse, arenas,
  guard bytes) silently breaks the "fresh memory is zero" assumption that
  callers depend on.

## The contract (library-first)

Push the invariant into **one library-owned helper**, called everywhere, not
reimplemented inline per path/target:

- A single RTL primitive — `PXXZeroManagedSlot(addr, bytes)` (or reuse/extend
  `PXXMemZero`) — that is the *only* place the "this slot is now nil" guarantee
  is produced. Frame-entry managed-local init calls it; the per-target inline
  ladders in `parser.inc` collapse to one call (the x86-64/i386/aarch64 paths
  already call `PXXMemZero` for the >ptr-size case — extend to all sizes/targets
  and drop the bespoke single-slot stores).
- GetMem guarantees zeroed payload on **both** paths (make the bump path's
  "fresh page" assumption explicit/owned, or zero unconditionally), so callers
  state one precondition: "GetMem returns zeroed memory," full stop.

One helper, one guarantee → the bump-vs-freelist split and the per-target ladder
stop being places a bug can hide.

## Why now (ordering)

- arm32 startup segfault likely **disappears at source** (stale-slot mechanism
  removed, not patched at the `DecRef` site).
- Cross-target codegen (Int64 and beyond) then lands on stable ground instead of
  chasing a crash that isn't even in the new work.
- **Do it BEFORE more cross-target codegen, not retroactively.** Ripping a
  zeroing-helper refactor *under* already-committed, green-in-isolation Int64
  work = bigger diff, harder to keep fixedpoint byte-identical. Order matters
  going forward.

Anti-pattern to avoid: patching `DecRef` to tolerate garbage handles. That hides
the seam instead of closing it.

## Acceptance

- Managed-local frame-entry zeroing is a single library call on every target
  (no per-target inline ladder; xtensa/riscv no longer stubbed/"not supported").
- GetMem documents + guarantees zeroed payload on both allocation paths.
- arm32 startup segfault gone without a `DecRef`-side workaround.
- Self-host fixedpoint + cross-bootstrap byte-identical.

## Log
- 2026-06-16 — opened from the `not`-bug post-mortem (606abec). Framing: fix the
  seam, then the segfault class disappears — not "patch DecRef".
