# Rust frontend — umbrella

- **Type:** feature — umbrella (spans Track A + Track B)
- **Status:** backlog — design/scoping only, no code yet
- **Owner:** —
- **Opened:** 2026-07-03 (design discussion — see `devdocs/developer/historic/rust-frontend.md`)
- **Priority:** unranked — this is a scoping ticket, not a greenlit build

## Motivation

Add a Rust-syntax frontend (4th, after Pascal/Nil-Python/C) lowering to the
existing shared IR/backends, same shape as the C frontend's v80 bring-up
(`clexer.inc`/`cparser.inc`/`cpreproc.inc` → shared IR). Real-world target
used to scope this: `~/nextlevel` (chess engine, ~6.1k LOC own code) +
its 3 crates.io dependencies (`shakmaty` 16.2k LOC, `shakmaty-syzygy` 4.0k
LOC, `arrayvec`) — confirmed via `Cargo.lock` `source = "registry+..."`,
not vendored. Dependency source is ~3.3x the app's own code and exercises
harder features (generics+bounds, lifetimes, `macro_rules!`, `dyn Trait`,
`unsafe`/`MaybeUninit`) more than the app itself does.

## Explicit non-goals (decided up front, mirrors the borrow-checker precedent)

- **No borrow-checker soundness proof.** Ownership enforced at runtime via
  refcounting (`Rc`/`Arc`) + move-tracking + `Drop`, not a compile-time proof.
  Programs that are actually memory-safe compile and run correctly; programs
  that rely on the checker to *reject* unsafe code won't get that rejection.
  See `devdocs/developer/historic/rust-frontend.md`.
- **Lifetimes parsed, not enforced.** Accepted syntactically (generic params,
  `&'a T`), never checked. Dangling borrows are a runtime bug we don't catch —
  document loudly, don't pretend otherwise.
- **No tokio/async-ecosystem compatibility.** `async fn`/`.await` desugars onto
  PXX's existing stackful coroutine runtime (`coroutine_emit.inc`,
  `lib/rtl/coroutine.pas`, `lib/rtl/scheduler.pas`) — correct semantics for
  our own compiled async code, NOT wire-compatible with `Future`/`Poll`/`Pin`
  or any crate built on the real (stackless, poll-based) model.
- **No general `macro_rules!` hygiene/token-tree engine initially** — see
  [[feature-rust-macro-rules]] for the scope cut (builtins-as-intrinsics
  first).
- **Compiling arbitrary crates.io dependency source is explicitly out of
  scope for v1.** `shakmaty`/`shakmaty-syzygy`/`arrayvec`-shaped deps are
  either (a) hand-ported to a pxx RTL unit once the call surface is known, or
  (b) revisited only after the subset below is solid. Don't let one
  dependency's feature usage drag the whole ticket into full-Rust scope.

## What already exists to reuse (confirmed by reading the tree, not assumed)

- `AN_AWAIT`/`AN_YIELD`/`AN_COSWITCH` (defs.inc ~163-179) — async/generator
  AST nodes, coroutine-backed. Reuse for `async`/`.await`.
- `AN_INTF_FROM_CLASS`/`AN_INTF_CALL` (defs.inc ~186-189) — fat-pointer
  interface dispatch, same shape as `dyn Trait` (data ptr + vtable ptr).
- `GenericFuncs`/`GenericMethods`/specialization (defs.inc ~679-789) —
  monomorphization engine, reuse for Rust generics.
- ARC on managed strings/dynarrays — reuse for `Rc`/`Arc`.
- Lambda-lifted nested procs (defs.inc ~745, "Approach B") — reuse for
  closure capture.
- `tyVariant` (defs.inc ~625) — 8-byte-tag + 8-byte-payload tagged scalar;
  proto version of enum-with-data, too narrow for struct-payload variants
  (needs generalizing, see [[feature-rust-match-enum-payload]]).
- `palthreadobj.pas`, `channel.pas`, `__pxxatomic_*` — reuse for
  `std::thread`/`mpsc`/`Atomic*`.
- Class dtor/`.Free` — partial RAII precedent, not full arbitrary-type
  scope-exit (see [[feature-rust-drop-move-tracking]]).

## Sub-tickets

**Track A (compiler internals — shared AST/IR/symtab/backends):**

1. [[feature-rust-frontend-skeleton]] — `rlexer.inc`/`rparser.inc`, entry
   point, minimal expr/stmt subset. Unlocks everything else.
2. [[feature-rust-match-enum-payload]] — pattern-bind `match` + generalized
   tagged union (beyond `tyVariant`'s 16 bytes).
3. [[feature-rust-generics-trait-bounds]] — trait-bound checking on top of
   existing monomorphization.
4. [[feature-rust-dyn-trait-dispatch]] — vtable dispatch decoupled from class
   hierarchy (trait-impl-for-any-type).
5. [[feature-rust-drop-move-tracking]] — scope-exit destructor insertion +
   move-flag tracking. The correctness-sensitive one: wrong = silent
   double-free, not a compile error.
6. [[feature-rust-derive-macros]] — synthesize `Clone`/`Copy`/`Debug`/
   `Default`/`PartialEq`/`Eq` bodies from field lists.
7. [[feature-rust-macro-rules]] — `macro_rules!` scope cut (builtins as
   intrinsics first; full token-tree/hygiene engine deferred).
8. [[feature-rust-borrowed-slice-type]] — `&[T]`/`&str`-for-any-`T`: a
   non-owning ptr+len view distinct from owning dynarray/AnsiString.
9. [[feature-rust-misc-semantics]] — integer overflow mode
   (panic-on-debug/wrap-on-release flag) + `{}`/`{:?}` format-string
   mini-parser (backs `println!`/`format!`).

**Track B (lib/rtl, lib/pcl):**

10. [[feature-rust-rtl-core-types]] — `Option<T>`/`Result<T,E>`/`Box<T>`/
    `Vec<T>` as thin RTL wrappers over existing tagged-union/heap/dynarray
    machinery (depends on #2 for the tagged-union half).
11. [[feature-rust-rtl-concurrency]] — `std::thread::spawn`/`JoinHandle<T>`/
    `mpsc::channel`/`AtomicBool`/`AtomicU64` shims over
    `palthreadobj.pas`/`channel.pas`/`__pxxatomic_*`. Pure API-shape wrapper,
    no new primitive.
12. [[feature-rust-rtl-macros-io]] — `println!`/`format!`/`vec!`/`assert!`/
    `panic!` intrinsics wired to #9's format parser + existing `Halt`/
    exception machinery.

## Notes on scale (calibration, not a promise)

The C frontend went from v80 merge to lua-running-libc-free maturity over
dozens of incremental sessions (see `project_c_lua_bringup*` memory chain).
A Rust subset of this shape (no async-ecosystem-compat, no full
`macro_rules!` hygiene, no `dyn`-object-safety edge cases) is comparably
sized — no single sub-ticket above is a research problem, but the sum is a
multi-week project, not a multi-day one. #1 gates everything; #5 is the one
that must be correct on first landing (silent-corruption risk, not a
compile-error risk).

## Log
- 2026-07-03 — umbrella opened from a design discussion (see conversation
  log / `devdocs/developer/historic/rust-frontend.md`). Real-app gap
  analysis done against `~/nextlevel` + its 3 crates.io deps. No code
  written yet; skeleton (#1) branches off `master` under Track A per the
  usual C-frontend precedent when work starts.
