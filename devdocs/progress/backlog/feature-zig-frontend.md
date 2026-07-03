# Zig frontend — umbrella

- **Type:** feature — umbrella (spans Track A + Track B)
- **Status:** backlog — design/scoping only, no code yet
- **Owner:** —
- **Opened:** 2026-07-03 (feature request — filed next to [[feature-rust-frontend]])
- **Priority:** unranked — scoping ticket, not a greenlit build

## Motivation

Add a Zig-syntax frontend (5th, after Pascal / Nil-Python / C / Rust-planned)
lowering to the existing shared IR/backends, same shape as the C frontend's v80
bring-up (`clexer.inc`/`cparser.inc`/`cpreproc.inc` → shared IR). Zig is
**C-style / systems**: manual memory (explicit allocators, no GC), structs,
pointers, plain integers, C-like control flow — so it maps onto the current
statically-typed IR **directly**, much like C, and is a materially smaller lift
than the Rust frontend (no ownership/move model, no trait system). This is the
easier of the two new-frontend requests; JS was parked as architecturally
out-of-scope (see [[feature-js-frontend-parked]]).

## Explicit non-goals (scope cuts up front, like the C/Rust precedent)

- **No `comptime` metaprogramming engine initially.** `comptime` is Zig's
  compile-time-evaluation + generics substrate — a full interpreter over the
  AST. v1 handles only trivially-const `comptime` (constant expressions,
  `comptime`-known array sizes) as ordinary const-eval; generic functions
  (`fn f(comptime T: type, ...)`) come later via the existing monomorphization
  engine (`GenericFuncs`, defs.inc), not a general comptime VM.
- **No async/await ecosystem.** Zig's colorblind async is evolving upstream and
  is not a v1 target; if pursued, desugar onto PXX's stackful coroutine runtime
  (`coroutine_emit.inc`) like the Rust plan — correct for our own code, not
  wire-compatible with any Zig async runtime.
- **No `build.zig` / package manager / build system.** Compile single files /
  a fixed file set, as the C frontend does — not the Zig build graph.
- **No full `std`.** A thin `lib/zigrtl` subset (basic `std.debug.print`,
  `std.mem`, allocators-as-thin-wrappers-over-our-heap) grown on demand, the
  way `lib/crtl` grew for C. Not std.io/net/fs breadth up front.
- **Compiling arbitrary upstream Zig packages is out of scope for v1** — same
  rule as the Rust umbrella: hand-port a call surface if needed, don't let one
  dependency drag the ticket into full-Zig scope.

## What already exists to reuse (confirmed reusable machinery)

- **C-frontend bring-up pattern** — `clexer`/`cparser`/`cpreproc` → shared
  AST (`AN_*`) → shared IR. Zig's `zlexer`/`zparser` follow the identical
  shape; the whole IR/backend/ABI/ELF stack is unchanged.
- **Structs / pointers / fixed & dynamic arrays / integers** — already first-
  class in the IR; Zig structs, `[N]T`, `[]T` slices, `*T` map onto them.
- **Error unions (`E!T`) and optionals (`?T`)** — a tagged
  value (payload + error/null tag). `tyVariant` (defs.inc) is the 16-byte
  proto; the generalized tagged-union work planned for Rust
  ([[feature-rust-match-enum-payload]]) is the SAME primitive — share it.
- **`defer` / `errdefer`** — scope-exit execution; the scope-cleanup machinery
  (`IRLowerCleanupToDepth`, class dtor insertion) is the precedent to reuse,
  same family as the Rust drop work ([[feature-rust-drop-move-tracking]]).
- **Slices `[]T` / `[]const u8`** — non-owning ptr+len view; identical need to
  Rust's [[feature-rust-borrowed-slice-type]] — share the type.
- **Monomorphization** (`GenericFuncs`/specialization, defs.inc) — backs
  `comptime`-generic functions when that phase lands.

Much of the Rust RTL/type groundwork (tagged unions, slices, drop/defer) is
directly shared with Zig — sequencing the two together would amortize it.

## Sub-tickets (split when work starts — don't flood the board yet)

**Track A (compiler internals — shared AST/IR/symtab/backends):**

1. **zig-frontend-skeleton** — `zlexer.inc`/`zparser.inc`, entry point (`.zig`
   dispatch in `compiler.pas`), minimal subset: `fn`, `pub`, integers, `var`/
   `const`, `if`/`while`/`for`/`switch`, blocks, `return`, basic operators.
   Gates everything else. Mirrors C-frontend skeleton scope.
2. **zig-structs-and-pointers** — `struct`, field access, `*T`/`*const T`,
   `&x`, `.*` deref, `[N]T` arrays.
3. **zig-optionals-and-error-unions** — `?T`, `E!T`, `orelse`, `catch`,
   `try`, `if (opt) |x|` capture, `unreachable`. Depends on the generalized
   tagged-union primitive (shared with [[feature-rust-match-enum-payload]]).
4. **zig-slices** — `[]T`/`[]const T` ptr+len views, slicing `a[lo..hi]`,
   `.len`/`.ptr`. Shared with [[feature-rust-borrowed-slice-type]].
5. **zig-defer-errdefer** — scope-exit + error-path-exit execution over the
   existing cleanup machinery.
6. **zig-comptime-generics** — `fn f(comptime T: type, ...)` via
   monomorphization; `comptime`-known sizes. NOT a general comptime VM.
7. **zig-switch-and-tagged-enum** — `switch` on enums/tagged unions with
   payload capture; `enum`/`union(enum)`.

**Track B (lib/zigrtl):**

8. **zig-rtl-core** — allocators as thin wrappers over the pxx heap
   (`std.heap.page_allocator`-shape), `std.debug.print` / `std.log` wired to
   existing write machinery, `std.mem` basics (`copy`, `eql`, `span`).

## Notes on scale (calibration, not a promise)

Smaller than the Rust umbrella (no ownership/move/trait system), comparable to
the C frontend's multi-session bring-up. #1 gates everything. The
correctness-sensitive piece is `defer`/`errdefer` ordering and error-union
propagation (wrong = skipped cleanup / wrong error path, a runtime bug, not a
compile error) — land those with tests first. Sequence with the Rust
tagged-union/slice/drop work to share the primitives.

## Log
- 2026-07-03 — umbrella opened from a feature request; filed alongside the Rust
  frontend family. Zig chosen over JS (parked — see
  [[feature-js-frontend-parked]]) because it is C-style and maps directly onto
  the existing IR. No code yet; skeleton (#1) branches off `master` under
  Track A per the C-frontend precedent when work starts.
