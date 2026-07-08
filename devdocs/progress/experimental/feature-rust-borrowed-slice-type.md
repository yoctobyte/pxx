---
prio: 45  # auto
---

# Rust frontend — borrowed slice type (`&[T]`, generalized `&str`)

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 8/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

`&str` (ptr+len over string data) is trivial — reuses AnsiString's existing
length-prefixed layout read-only. The general case is the actual gap:
`&[T]` for arbitrary `T` needs a **non-owning** ptr+len view type. Every
existing PXX length-prefixed layout (AnsiString, dynarray) is
heap-owning/refcounted — a slice borrows into someone else's storage
(a stack array, part of a `Vec`, etc.) and must never free/refcount it.

## Scope

- New value-type shape: `{ data: Pointer; len: NativeInt }`, no heap header,
  no refcount touch on copy/drop.
- Bounds-checked indexing by default (matches Rust); `unsafe` indexing
  (`get_unchecked`) skips the check — see [[feature-rust-frontend]]'s
  unsafe-block scope, already covered by PXX's existing raw-pointer support.
- Slicing syntax (`arr[1..3]`) produces a slice value pointing into the
  original storage, not a copy.

## Acceptance

- A slice over a stack array, a `Vec<T>`, and a string literal all produce
  correct ptr+len values; indexing and iteration work; no spurious
  free/refcount on scope exit of the slice binding itself (only the
  underlying owner frees).
- Bounds check fires on out-of-range index outside `unsafe`.

## Log
- 2026-07-09 — MINIMAL subset landed on master (Track R ports-back pass,
  commit bbd15a52), WITHOUT the shared tySlice machinery this ticket
  scopes: `&a[lo..hi]` over fixed arrays as an auto-registered
  __ptr+__len UClass (the Zig frontend's representation), `s[i]`
  read/write via raw i64 pointer math + AN_DEREF, `s.len()`. Locals
  only — no slice params/returns, no &str, no re-slicing. The full
  ticket (a real non-owning view type through the ABI) remains open and
  is exactly the AST/IR-work upscale case experimental/README.md
  describes.

- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
