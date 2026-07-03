# Rust frontend RTL — thread / atomics / mpsc shims

- **Type:** feature — Track B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 11/12. Depends on
  [[feature-rust-frontend-skeleton]] and
  [[feature-rust-generics-trait-bounds]] (`JoinHandle<T>` is generic).

## What it does

Pure API-shape wrappers — every underlying primitive already exists in
`lib/rtl`, confirmed by reading the tree, nothing new at the runtime level:

- `std::thread::spawn`/`JoinHandle<T>` → `lib/rtl/palthreadobj.pas`
  (`TThread`-style object already handles create/join).
- `std::sync::mpsc::channel` → `lib/rtl/channel.pas` (already exists).
- `AtomicBool`/`AtomicU64`/etc. → `__pxxatomic_xchg`/`cas`/`add` intrinsics
  (already exist, `AN_ATOMIC` defs.inc ~263).
- `Arc<T>` around these → existing ARC machinery, same as
  [[feature-rust-rtl-core-types]]'s `Box`/`Rc` reuse.

Real-world confirmation: `~/nextlevel/engine/src/search.rs` +
`src/uci.rs` use `std::thread::spawn`, `JoinHandle`, `mpsc::channel`,
`AtomicBool`, `AtomicU64`, `Arc<AtomicBool>` — this is the concurrency
surface the target app actually needs, nothing more exotic (no
`RwLock`/`Condvar` in that codebase as of the audit).

## Acceptance

- `thread::spawn(move || ...)` + `.join()` round-trips a closure through
  `palthreadobj.pas`'s existing thread object, return value flows through
  `JoinHandle<T>::join() -> T` correctly (generic — needs
  [[feature-rust-generics-trait-bounds]]).
- `mpsc::channel()` send/recv across threads works via `channel.pas`.
- Atomic load/store/CAS on `AtomicBool`/`AtomicU64` match the requested
  `Ordering` semantics closely enough for correct producer/consumer code
  (x86-64: most orderings collapse to the same instruction anyway).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
