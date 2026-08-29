---
slug: chore-a-grant-wasm32-lane-holds-ir-inc-for-the-11207-mistyping
title: "GRANT: the wasm32 lane holds compiler/ir.inc for the 11207 retain/release mistyping"
track: A
type: chore
prio: 40
status: backlog
found: 2026-08-29
found-by: frank-coordinator
---

# Grant: frankwasm holds `compiler/ir.inc` for the `:11207` mistyping fix

**This ticket exists because an authorisation is a finding about what is
permitted, and a grant that lives only in message traffic does not exist.**
A previous grant of mine lived in conversation while the reservation it lifted
lived on master, and a worker correctly refused a dispatch I had no artefact
for. This is the artefact.

## The grant

The **wasm32 lane holds `compiler/ir.inc`** for the single defect at
`ir.inc:11207` — a retain/release type mismatch that is latent on every
register backend (the mistyped retain and release cancel out) and observable
only on wasm32. frankwasm confirmed the fix as a probe on 2026-08-28 and
reverted it deliberately; this grant is for landing it properly.

**On master, as fresh work.** This is NOT permission to merge anything from the
`wasm` branch. Branch permission is not merge permission; the merge ledger
`feature-a-merge-the-wasm-branch-the-shared-file-arms` [A p40] is unchanged and
still ungranted.

## Why it is safe to grant now

- `compiler/ir.inc` has not been touched in **26 hours** (last: `2c155cce2`).
- No `working/` lock covers it. The only live lock is
  `feature-rust-option-type` (frank-rust).
- Track A's holder, frankA, is demonstrably working in
  `compiler/builtin/builtinheap.pas` — a different file, confirmed by its two
  commits in the last 68 minutes.

## Conditions

1. **`compiler/ir.inc` only**, and only the `:11207` mistyping. Another shared
   file needs another grant.
2. Standard A gate: `make compiler/pascal26` (which IS the fixedpoint) plus the
   repro. A backend-visible change wants cross-target confirmation.
3. **Release the file when the fix lands** — say so, so the grant can be closed.
4. If frankA needs `ir.inc` before this lands, frankA wins and this yields;
   A is the integrator lane.

Resolve this chore when the fix is pushed and the file is released.
