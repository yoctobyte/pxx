---
prio: 65  # auto
---

# Rust frontend — generics with trait bounds

- **Type:** feature — Track A (Track R)
- **Status:** done
- **Owner:** Claude (~/frank2, branch `feature/rust-frontend-skeleton`)
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 3/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

Extend the existing monomorphization engine (`GenericFuncs`/`GenericMethods`,
defs.inc ~679-789 — already does Pascal-generic specialization) to accept
`where`-clause / inline trait bounds (`fn f<T: Display>(x: T)`) and check
that the bound is satisfied at specialization time (the concrete `T` must
have an `impl` of the required trait reachable).

Not new conceptually — same specialize-per-call-site machinery already
proven for Pascal generics — but real engineering volume: real-world dep
code (`shakmaty` alone: 123 generic functions, 63 `impl<T>` blocks, 57
`where` clauses) leans on this heavily, more than the app code itself does.

## Scope

- Bound satisfaction check at specialization, not a general trait-coherence
  solver — reject with a clear error if unsatisfied, don't try to be clever.
- No specialization/overlapping-impl resolution beyond what's needed for a
  single unambiguous match (Rust forbids overlapping impls anyway).
- Multiple bounds (`T: Display + Clone`) — AND of individual checks.

## Acceptance

- Generic function/struct with a single trait bound specializes correctly
  per call site, rejects a concrete type missing the trait with a clear
  compile error (not a silent miscompile or generic IR crash).
- Multi-bound case works.
- Existing Pascal-generic tests unaffected (this extends, doesn't replace,
  the existing specialization path).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
- 2026-07-03 — landed with a **private, token-copy specialization
  engine** in `rparser.inc` instead of reusing the shared Pascal
  `GenericFuncs`/`Specializations` machinery (defs.inc ~679-789): that
  pipeline is built around Pascal's explicit `specialize T<Concrete>`
  surface syntax and its own materialization path; Rust's generics are
  inferred from the first call-site argument, different enough that
  forcing a fit would have meant deep coupling to Pascal-specific parsing
  rather than a fit. No new `TTypeKind`, no new AST node, no Track A
  hand-off — same "reuse the low-level primitives, keep the frontend
  bookkeeping private" pattern as sub-tickets 1-2.
  - **impl blocks** (inherent and trait): each method becomes an ordinary
    `RegisterProc`'d function named `"Type::method"` with `self` prepended
    as param 0. `impl Trait for Type` records `(TypeCi, TraitName)` in a
    private table; bound checking is pure membership in it — "not a
    general trait-coherence solver," matching the ticket's own scope note.
  - **Generic fns**: `fn f<T: Bound>(x: T)` is buffered (token span, never
    compiled directly); each call site copies that span to the end of the
    shared token buffer substituting every `T` with the concrete type name
    (inferred from the first argument), then compiles the copy as an
    ordinary mangled `f$Concrete` function, memoized via `FindProc` so a
    repeat call with the same concrete type reuses it.
  - Two real bugs found via testing, not inspection, both fixed:
    1. `RegisterProc` always defaults `Params[i].IsRef` to `False`; `self`
       (and now struct-typed free-function params, newly allowed by this
       ticket) need it explicitly set `True` or the caller passes the
       struct by raw value while the callee's `AllocParam(isRef=True)`
       dereferences it as a pointer — reads garbage, segfaults.
    2. Specialization triggers **mid-parse** of whatever function called
       the generic one (e.g. inside `main`'s own body, before `main`'s
       body is handed to `CompileAST`) — the specialized fn's emitted
       code landed right after the caller's already-emitted prologue with
       nothing to jump over it, so execution fell from the caller's
       prologue straight into the specialized function's body. Fixed with
       a bracketing `jmp`, the same pattern `ParsePyProgram` uses to
       insert runtime setup code mid-stream.
  - Also hit a **pre-existing, documented PXX self-host parser
    limitation** (same "const-expr gap" already noted on `TProc.Params` in
    defs.inc): a record field's array bound can't be `CONST-1`, only a
    literal, under self-host (FPC has no such issue). Worked around with a
    literal + a comment, per the existing precedent — not a new bug, not
    something requiring a Track A ticket, just a known rough edge to route
    around.
  - This ticket's own struct-typed generic-function argument path required
    relaxing sub-ticket 1's "no struct-typed function parameters" ABI
    restriction (now: struct/enum params are allowed, always passed by
    address; struct/enum *return values* stay out of scope, unchanged).
  - Verified: inherent impl method call, trait-bounded generic calling a
    trait method on the concrete type, multi-bound (`T: Show + Doubler`)
    satisfied case, plain scalar generic (`identity<T>`), and the
    rejection path (calling a bound-requiring generic with a type that has
    no matching `impl` errors clearly at compile time, does not
    miscompile or crash). Sub-ticket 1/2 regression tests (t1/t2/t3)
    still pass unchanged. `make bootstrap` self-host stays byte-identical;
    `make -k test` green except the same pre-existing unrelated
    environment failure noted in sub-ticket 1. Also spot-checked this
    ticket's own g1-g4 test programs against the **self-hosted** compiler
    (not just FPC-built) — all four pass correctly there too, unlike
    t1.rs which still reproduces [[bug-selfhost-multifn-ifelse-miscompile]]
    exactly as before (confirms that bug is unaffected by this ticket's
    changes, not newly triggered by them).
  - Documented narrowing: one type parameter per generic fn (no `<T, U>`);
    T inferred from the first argument only; a struct/enum argument to a
    generic function must be a plain variable (same "no general
    resolve-this-node's-record-type helper" narrowing as sub-ticket 2's
    match scrutinee); generic STRUCTS (`struct Box<T>`) are explicitly
    deferred — a struct specialization needs a whole new `UClass` per
    concrete type, a materially separate feature axis from function
    specialization the umbrella's acceptance text lumps in but this
    landing does not cover.
  Next: sub-ticket 4, [[feature-rust-dyn-trait-dispatch]].
- 2026-07-04 — merged to `master` (fast-forward, `a71356c`) alongside
  sub-tickets 1-2. Unofficial/unsupported — see sub-ticket 1's log for the
  rationale. Stays `working/`; sub-ticket 4 is next.
- 2026-07-08 — resolved, commit a71356c3.
