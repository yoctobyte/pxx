---
prio: 45  # auto
---

# Cross-frontend interop contract — umbrella

- **Type:** feature — umbrella (Track A: AST/IR/symtab/ABI/backends)
- **Status:** backlog — design/scoping only, no code yet
- **Owner:** —
- **Opened:** 2026-07-05 (design discussion, Track B session)
- **Priority:** unranked — scoping ticket, not a greenlit build

## Motivation

PXX already has 2 frontends beyond Pascal (C, Nil-Python) with a 3rd landing
(Rust, actively in `working/`) and a 4th scoped (Zig, [[feature-zig-frontend]]).
Interop today is one-directional and ad hoc per frontend: Pascal/Nil-Python
import C headers and call into shared libraries via the "magic link" model
(`docs/targets/cross-languages.md`, `docs/targets/c-frontend.md`). There is no
first-class way to compile a Pascal unit, a C file, and (soon) a Rust module as
peer translation units in one build with calls in *both* directions — each
`pxx` invocation picks one frontend by main-file suffix.

With 2 more frontends about to exist, each is at risk of bolting on its own
bespoke interop shim (Rust's own C-call convention, Zig's own, diverging from
what C/Nil-Python already do) unless the contract is written down once, now,
before the second and third frontend duplicate solved problems.

## What already exists (foundation, confirmed reusable)

- All frontends lower to the **same shared AST/IR/backends/ABI/ELF pipeline**
  (`compiler/ir*.inc`, the backends) — the hard part (codegen, calling
  convention, ELF emission) is already unified. This is not starting from zero.
- **C header import** (Pascal/Nil-Python → C): read a C header, generate
  callable bindings, link against the C symbol at the "magic link" step.
- **Nil Python's autotyping**: calls imported C APIs directly through the same
  backend, with automatic C-parameter return-lifting.
- **C frontend's own ABI**: already matches the System V AMD64 calling
  convention other frontends target, since backends are shared.

## The actual gap

1. **No symbol/name-mangling convention document.** Each frontend currently
   decides its own exported-symbol naming ad hoc. Nothing stops Pascal's
   `TFoo.Bar` mangling scheme from colliding with, or being unreachable from, a
   future Rust `impl Foo { fn bar() }` unless a shared rule exists.
2. **No "peer translation unit" build model.** Cross-language calls today
   require going through a C header as the interface language, even when both
   sides are PXX-compiled (not calling into libc or a real C library) — e.g. a
   Pascal program directly linking a Rust module's exported function without
   hand-writing a C shim header for it.
3. **No written-down type-mapping table across frontends.** What does a Pascal
   `AnsiString` look like from C's side (today: it doesn't cross uninterpreted,
   headers only expose `PChar`/plain pointers)? What will a Rust `&str`/`Vec<T>`
   look like from Pascal? Undefined until asked, per frontend, per feature.
4. **Whether "mixed build" means one invocation with multiple source files
   (each auto-dispatched by extension) vs. `--emit-obj` per language + a
   separate link step** (cheaper, closer to the existing magic-link model,
   probably the pragmatic v1 answer) is undecided.

## Explicit non-goals (v1 scope cut, following the C/Rust/Zig precedent)

- **Not a universal FFI marshalling layer.** No attempt to make every type in
  every frontend transparently convertible to every other — start with
  primitives, pointers, and plain structs/records (the C-interop-shaped
  subset), same boundary C interop already draws.
- **Not retrofitting existing single-frontend builds.** This is additive;
  `pxx foo.pas` alone keeps working exactly as today.
- **Not solving generics/trait/comptime-generic interop.** Cross-language
  calls target monomorphized, concrete-typed functions only — a Rust generic
  or Zig `comptime`-generic fn is only callable cross-language after
  instantiation, not as a template.

## Suggested sub-tickets (split when scoping firms up — don't flood the board)

1. **interop-symbol-convention** — write down (and where needed, adjust) the
   exported-symbol / name-mangling rule every frontend must follow so any two
   frontends' compiled objects can link and call each other without a C-header
   detour for non-libc, PXX-to-PXX calls.
2. **interop-type-mapping-table** — a living reference doc (candidate:
   `docs/targets/cross-languages.md` grows this) enumerating what each
   frontend's primitives/pointers/structs look like from every other frontend's
   side. Grows as each new frontend lands, not all at once.
3. **interop-peer-unit-build** — decide + implement the actual build path
   (multi-source-per-invocation vs. `--emit-obj` + link); wire `tools/`/`make`
   support and a worked example (e.g. a Pascal program calling a Rust-compiled
   function directly, once Rust skeleton exists).
4. **interop-docs-rewrite** — once 1-3 land, rewrite
   `docs/targets/cross-languages.md` from "experimental frontends exist" to an
   actual how-to for calling across languages, with the type-mapping table
   linked.

## Acceptance (for the umbrella; each sub-ticket has its own)

A written interop contract exists that Rust and Zig frontends can each be
checked against as they land (not retrofitted after the fact); at least one
worked cross-language example (e.g. Pascal ↔ Rust, once Rust reaches a callable
subset) builds and runs via the chosen peer-unit build path; `docs/targets/
cross-languages.md` reflects the real mechanism, not just C-header import.

## Log
- 2026-07-05 — filed from a Track B design discussion: user asked whether
  future multi-frontend mix-and-match (C, Nil-Python, Rust, Zig) deserves its
  own ticket before Rust/Zig each invent their own ad hoc interop path. Track A
  ticket — Track B does not build this; hand off / pick up under Track A.
