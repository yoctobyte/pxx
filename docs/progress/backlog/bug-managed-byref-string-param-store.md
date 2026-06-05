# Managed by-ref AnsiString params: store-through-var no-ops / segfaults

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-managed-string-default
- **Opened:** 2026-06-06 (from plan-refcounted-compiler-strings.md gap B)

## Symptom (under `{$define PXX_MANAGED_STRING}`)

A `var`/`out` AnsiString param is passed **by value** (a copy of the 8-byte
handle), not as the address of the caller's slot, so callee stores never reach
the caller and borrow/release bookkeeping on the copy is wrong. Verified
2026-06-04:

| Callee op | Frozen | Managed (today) |
|---|---|---|
| `s := 'hello'` (assign-through-var) | caller updated | silently no-ops |
| `s := s + '!'` (concat-through-var) | works | **segfault** |
| `SetLength(s, 3)` (setlength-through-var) | works | silently no-ops |

## Why it matters

Correct managed by-ref store must deref the ref to the caller's slot, release the
old handle there, store the new handle, retain as needed. That store path does
not exist yet. The compiler uses this idiom at ~44 sites, so it is load-bearing
and the true first blocker for the managed-string default.

## Relation

Sub-blocker of
[`feature-managed-string-default`](feature-managed-string-default.md). Frozen
(default) strings are unaffected.

## Acceptance

Assign/concat/`SetLength` through a `var` AnsiString param updates the caller
correctly under managed mode (no no-op, no segfault); a regression covers all
three rows.

## Log
- 2026-06-06 — ticket opened from plan-refcounted-compiler-strings.md gap B.
