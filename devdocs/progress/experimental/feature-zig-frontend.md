---
prio: 45  # auto
---

# Zig frontend — THEORETIC COMPLETION reached (frontend-side); experimental

- **Type:** feature — umbrella (spans Track A + Track B)
- **Status:** experimental — everything reachable by pure parse-time
  desugaring onto the existing IR is DONE and tested (2026-07-08); what
  remains needs shared machinery (see below) and is low-prio by the
  experimental-frontends rule (experimental/README.md)
- **Owner:** —

## Theoretic completion (2026-07-08, Track Z — user-directed)

Sub-tickets 3/4/5/7 landed in one pass, still zero shared-internals edits
(zparser.inc + one lexer char + test + Makefile). The trick throughout:
every "missing primitive" was faked with vocabulary the IR already has —
the same UClass tag+payload shape the Rust skeleton's enums pioneered:

- **#7 switch** — hidden scrutinee temp + AN_IF chain (arm value lists OR
  together; blocks / expressions / `return` arms; `else`). No ranges.
- **#5 defer/errdefer** — fn-level parse-time stash, replayed in reverse
  at every exit; normal exits replay defer, error exits errdefer+defer.
  Return value evaluates into a hidden temp BEFORE the replay (Zig order).
  Deviation: registration is lexical, fn-scoped.
- **#3 optionals `?T`** — auto-registered UClass ("?i64") with __has/__val;
  `null`, assignment, `if (x) |v|` capture (fresh local + prepended field
  read, the Rust match-bind trick), `orelse` (AN_TERNARY), `.?` unwrap.
  Locals only.
- **#3 error unions `!T`** — errno-style global `__zig_err` slot with a
  caller-clears convention; error names auto-register (codes from 1);
  `return error.X` (defers replay first, slot set after), `try f()`
  (statement or whole var-init; propagates via errdefer+defer replay +
  exit), `f() catch v` / `catch |e| { }`, `error.X` as a comparable value.
  Scalar payloads ride the normal return register.
- **#4 slices (minimal)** — auto-registered UClass ("[]i64") with
  __ptr/__len; `a[lo..hi]` (AN_ADDR over AN_INDEX for the base address),
  `s[i]` read/write via raw i64 pointer math + AN_DEREF (the C frontend's
  decay trick), `s.len`. Initializer-position slicing of fixed arrays only.

Test `test/test_zig_advanced.zig` (switch/defer/errdefer/optionals/error
propagation/slices in one program) wired into `make test`. Gate: all three
Zig tests green, testmgr quick 11/11, self-host fixedpoint byte-identical.

**Probe verdict: still no shared-internals bug** — AN_TERNARY, AN_DEREF on
computed addresses, AN_ADDR over AN_INDEX, deep nested AN_SEQ/AN_IF chains
from desugaring all worked as documented. One self-inflicted lesson worth
recording: the paramless-recursion pitfall (bare `ZParseStatement` reads
the Result alias instead of recursing) bit AGAIN inside the defer
dispatch — third frontend it has bitten; see frank2-paramless-name-semantics.

## Sub-ticket #6 landed too (2026-07-09, type-param subset)

After the user pointed out Pascal generics were mostly parser-side, #6
followed the same route: `fn f(comptime T: type, ...)` monomorphized by
token-buffer substitution (rparser's RSpecializeGenericFn ported as
ZSpecializeGenericFn — Zig is easier: the type arrives explicitly as the
first call argument, no inference). Mangled `f$i64` specializations,
cached; comptime param dropped from the copy; mid-stream jmp bracketing
reused; two Zig-specific hazards handled (caller's defer stash and
CurProc/FrameSize saved around the nested compile). Explicitly NOT a
comptime VM: no comptime values, control flow, or builtins.

**What remains is exactly the non-frontend work** (parked, would upscale to
Track A only on its own merits per experimental/README.md):
- a real comptime VM (#6's full form) — values/control-flow/builtins.
- record-ABI shapes — optional/struct/slice params and returns.
- std breadth (#8, lib/zrtl) — Track B, on demand.
- real tySlice / tagged-union primitives — shared with the Rust tickets
  ([[feature-rust-borrowed-slice-type]], [[feature-rust-match-enum-payload]]).

## Sub-ticket 2 landed (2026-07-07, Track Z — user-directed scaffolding pass)

**zig-structs-and-pointers** done, purely frontend-side as the gap map
predicted (zparser.inc + test + Makefile only; zero shared-internals edits):

- **Structs:** top-level `const Name = struct { f: T, ... };` (scalar fields)
  registered via the same AddUClass/AddUField prescan rparser.inc uses;
  `var s: Name = undefined;`, field read/write `s.f`, struct-literal init
  `var s = Name{ .f = expr, ... };` lowered to per-field AN_ASSIGNs (the
  Rust no-construct-node shape).
- **Pointers:** `*T` / `*const T` to scalars — `&x` (AN_ADDR, plain vars
  only), `p.*` read + assignment target (AN_DEREF), pointer locals
  (annotated or inferred from `&x` via the AN_ADDR operand's symbol) and
  pointer fn params (8-byte scalar in the same SysV register slots;
  pointee recorded through LastTypePointer* → AllocParam).
- **Arrays:** `var a: [N]T = undefined;` (AllocArray, 0-based), `a[i]`
  read/write (AN_INDEX), `a.len` folded to an AN_INT_LIT constant.
- Statement-level postfix lvalues (`s.f = e;` / `a[i] = e;` / `p.* = e;`)
  parse as expression-then-`=` (plain `=` only; compound stays
  plain-variable-only). Postfix is single-level by construction (fields
  are scalar, so chains cannot arise).

Test `test/test_zig_structs.zig` wired into `make test`. **Probe verdict:
again no shared-internals bug** — record/pointer/array lowering worked
first try; self-host fixedpoint byte-identical. Cross-target matrix
offloaded to Track T per the watcher protocol.

## Skeleton landed (2026-07-06, Track Z)

Sub-ticket **#1 (zig-frontend-skeleton)** is done, mirroring the Ada-skeleton
precedent exactly (additive only: `compiler/zlexer.inc` + `compiler/zparser.inc`
new files, `isZig` flag + `.zig` dispatch in compiler.pas, one-line `isZig`
var in defs.inc — no new AST nodes, no new IR, no backend work). zparser
reuses rparser.inc's node helpers (RSeqAppend/RMakeIdent/RBinOp/RWiden), so
the two C-family skeletons share plumbing.

**Landed subset:** top-level `[pub] fn` (≤4 scalar params, i8–u64/usize/
isize/bool/void), calls + recursion, `var`/`const` with type inference and
`= undefined`, assignment + compound (`+=` etc), if/else-if/else, while with
`: (continue-expression)`, range `for (lo..hi) |i|` (exclusive hi, per Zig),
break/continue, and/or, `_ = expr;` discard, `const std = @import("std");`
header swallowed, and `std.debug.print("fmt", .{args})` lowered onto
AN_WRITE/AN_WRITELN with `{}`-placeholder splitting (segments point straight
into the fmt token's TokChars — no copies). Test: `test/test_zig_skeleton.zig`
wired into `make test` next to the Ada one.

**Probe verdict: no shared-internals bug found this pass** — shared pipeline
(AN_* → IR → x86-64) handled the Zig shapes first try. Both bugs hit while
building were frontend-local: (1) Zig integer `/` initially mapped to tkSlash
= Pascal REAL division → double bits reinterpreted as int64 garbage; fixed by
lowering `/` to tkDiv (trunc div) since all skeleton types are integers —
note rparser.inc still maps Rust `/` to tkSlash, same latent hazard, its
tests just never divide ([[feature-rust-frontend]], worth a one-line note
there); (2) a `{ past } }` comment-brace typo in my own code.

**Known deviations (accepted, documented in zparser.inc header):** `continue`
inside `while ... : (expr)` skips the continue-expression (Zig runs it);
`const` mutability not enforced; no overflow safety; `{{ }}` fmt escapes
unhandled; x86-64 only.
- **Opened:** 2026-07-03 (feature request — filed next to [[feature-rust-frontend]])
- **Priority:** unranked — scoping ticket, not a greenlit build

## Reframed under the esoteric-frontend-probe category (2026-07-05)

Parked as a full-language effort (below), but a **skeleton-only pass** (lexer/
parser for a trivial subset, lowering onto existing IR, no comptime engine) is
back in scope — not to make Zig usable, but as a bug-probe against shared
internals. See [[feature-esoteric-frontend-probes]] for the category rule.

## Why parked (2026-07-05, user decision — rationale corrected 2026-07-05)

Original log entry claimed comptime's recursive/Turing-complete evaluation
"undermines determinism" and conflicts with the byte-identical fixedpoint
self-host gate. **That claim was wrong and is withdrawn.** Recursion and
Turing-completeness threaten *termination* (an unbounded comptime loop — hence
Zig's own branch-quota limiter), not determinism: a pure interpreter with no
access to wall-clock/randomness/filesystem/mutable global state gives the same
output for the same input regardless of recursion depth. And the fixedpoint
gate is about the PXX *compiler itself* (written in Pascal) reproducing
byte-identically across bootstrap stages — a Zig frontend's comptime
interpreter only runs while compiling Zig *source*, never during the
compiler's own self-compile, so it cannot threaten a gate it is never part of.

**Actual reason to park:** pure engineering scope, not architectural risk.
`comptime` is pervasive (not a corner feature — no separate generics syntax;
generics, `@TypeOf`, conditional compilation, and most of `std` all lean on
it), and the builtin surface is large (`@import`, `@sizeOf`, `@ptrCast`,
`@field`, …, each comptime-typed) with no "ignore and link" escape hatch the
way C headers give other frontends. See "Notes on scale" below — that section
already had the honest framing; the determinism paragraph was an unnecessary
and incorrect addition on top of it.

**Decision: scope an Erlang frontend first** — see
[[feature-erlang-frontend-scoping]], on its own merits (different engineering
domain: runtime/scheduler work vs. a compile-time interpreter), **not** because
it is "more deterministic" — Erlang's actor-model preemptive scheduling is
itself a classically nondeterministic *runtime* execution model (message
arrival order, process interleaving), so determinism was never a valid axis to
rank these two on. Revisit Zig if a comptime-style engine becomes independently
justified by something else needing it.

---

## Original scoping (2026-07-03, pre-park)

## Motivation

Add a Zig-syntax frontend (5th, after Pascal / Nil-Python / C / Rust-planned)
lowering to the existing shared IR/backends, same shape as the C frontend's v80
bring-up (`clexer.inc`/`cparser.inc`/`cpreproc.inc` → shared IR). Zig is
**C-style / systems**: manual memory (explicit allocators, no GC), structs,
pointers, plain integers, C-like control flow — so its *type theory* maps onto
the current statically-typed IR **directly**, much like C, with no
ownership/move/trait system to model (simpler than Rust in that dimension). But
"simpler type theory" does NOT mean trivial: reaching a subset that compiles
real Zig is likely non-trivial because `comptime` is pervasive and the builtin
surface is large — see "Notes on scale" below. It is the more *tractable* of the
two new-frontend requests (JS parked as architecturally out-of-scope, see
[[feature-js-frontend-parked]]), not an easy one.

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
- **Local type inference** (`tyAuto` + `EnableAutoVar`, parser.inc ~7731,
  10250) — PXX already infers a binding's type from its initializer for inline
  `var` (`var x := 5+3` in a statement block, `for var x in coll`). Verified
  empirically: `var x := 5+3` → Integer, `var s := 'hi'` → string. This is the
  SAME local-inference-from-initializer mechanism as Zig's `const x = expr` /
  `var x = expr`, so Zig's inferred bindings reuse the existing expression
  typer, not new machinery. Caveats: ours is currently gated on `EnableAutoVar`
  and scoped to inline `var` (global declaration-section `var` still needs an
  explicit type); Zig infers pervasively on every `const`/`var`. So the *local
  inference* is a genuine reuse win — but note the boundary vs. Zig's
  `comptime`-types below, which is the part we do NOT share.

Much of the Rust RTL/type groundwork (tagged unions, slices, drop/defer) is
directly shared with Zig — sequencing the two together would amortize it.

## AST/IR gap map — "pure frontend" vs "needs shared internals" (2026-07-04)

Verified against the current node/type inventory (defs.inc) + empirical checks.

**Lowers onto EXISTING AST/IR — a skeleton subset is pure lexer+parser, zero
Track-A internals change:**

| Zig construct | Reuses today |
|---|---|
| `fn` / params / `return` | procs |
| `i8..i64` / `u8..u64` / `usize` / `isize` | `tyInt8..Int64` / `tyUInt8..UInt64` / `tyNativeInt` / `tyNativeUInt` (1:1) |
| `if` / `while` / `for` / `switch`-on-int / blocks | `AN_IF` / `AN_WHILE` / `AN_FOR` / `AN_SWITCH` |
| `struct` + field access | `tyRecord` / `AN_FIELD` |
| `*T` / `&x` / `.*` | `tyPointer` / `AN_ADDR` / `AN_DEREF` |
| `[N]T` + indexing | arrays / `AN_INDEX` |
| plain `enum` | existing enum table (verified `Ord`) |
| `const x = expr` / `var x = expr` inference | `tyAuto` inline-var inference |
| value-exprs (`a ? b : c`-ish, `++`, comma) | `AN_TERNARY` / `AN_INCDEC` / `AN_COMMA` (from C frontend) |

**Needs NEW shared machinery (Track A internals — NOT lexer+parser), and each
overlaps an already-planned Rust ticket:**

| Zig construct | Missing today | Shared with |
|---|---|---|
| error unions `E!T`, `union(enum)` | generalized tagged union (only `tyVariant` 16-byte scalar + exception-match exist; no struct-payload tagged union) | [[feature-rust-match-enum-payload]] |
| slices `[]T` / `[]const u8` | no `tySlice`; a ptr+len non-owning view type | [[feature-rust-borrowed-slice-type]] |
| optionals `?T` | `?*T` = free (nullable ptr); `?i64`/`?struct` need has-value+payload (part tagged-union) | (tagged-union) |
| `try` / `catch` / `orelse` | propagation lowering over the above | — |
| `defer` / `errdefer` | MINOR: no `AN_DEFER`, but `AN_TRY_FINALLY` + `IRLowerCleanupToDepth` exist to desugar onto | [[feature-rust-drop-move-tracking]] |
| `comptime` + builtins (`@import`/`@TypeOf`/…) | biggest semantic gap — no comptime VM | (subset out of v1) |

**Bottom line:** skeleton (#1) = pure frontend, shippable, zero internals risk.
A *useful* subset = skeleton + the 3 shared additions (tagged-union, slice,
optional) — which ARE the Rust Track-A tickets. Zig and Rust share their hard
parts; building either advances the other. The "auto typing" is on the free
side; the tagged union is the real cost.

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

## Notes on scale — Zig is NOT an easy source (2026-07-03, user flag)

Earlier framing ("smaller lift than Rust") is only half true and needs
tempering. Zig has **no ownership/move/trait system**, so its *type theory* is
simpler than Rust's — but reaching a **practically useful subset** (one that
compiles real Zig) is likely NON-trivial, for reasons specific to Zig:

- **`comptime` is pervasive, not a corner feature.** Zig has no separate
  generics syntax — generics, type construction, conditional compilation, and
  much of `std` are all `comptime`. Our "no comptime VM" cut (a reasonable v1
  scope, like C/Rust's cuts) therefore excludes a LARGER fraction of real Zig
  than "no `macro_rules!`" excludes of real Rust. Everyday `fn f(comptime T:
  type)`, `@This()`, `@TypeOf`, `@hasField` etc. all lean on it. Impact:
  "compiles real programs" is gated on comptime-generics much *earlier* than
  the Rust equivalent.
- **Huge builtin surface.** `@import`, `@sizeOf`, `@intCast`, `@ptrCast`,
  `@field`, `@memcpy`, … (hundreds). Many are comptime-typed. Each needs
  frontend handling; there is no "ignore and link" fallback like C headers.
- **Error unions `!T` + optionals `?T` are threaded through everything** —
  idiomatic Zig, so the tagged-union + `try`/`catch`/`orelse` propagation must
  be solid EARLY (sub-ticket #3), not a late add.
- **`defer`/`errdefer` ordering + error-path cleanup** — correctness-sensitive
  (wrong = skipped cleanup / wrong error path, a runtime bug, not a compile
  error). Land with tests first.
- **Pre-1.0 moving target.** Zig syntax/semantics still shift between releases;
  pin a target version.
- **Allocator-passing idiom.** Every allocation takes an allocator param; `std`
  leans on it. Mappable to our heap, but pervasive.

Net: comparable-or-harder than the C frontend's multi-session bring-up to reach
"compiles real Zig", *despite* the simpler type theory — the cost is
`comptime` + builtins, not the type system. #1 gates everything; #3 (error
unions/optionals) and #6 (comptime-generics) are the real gates on usefulness.
Sequence with the Rust tagged-union/slice/drop work to share the primitives.

## Log
- 2026-07-03 — umbrella opened from a feature request; filed alongside the Rust
  frontend family. Zig chosen over JS (parked — see
  [[feature-js-frontend-parked]]) because it is C-style and maps directly onto
  the existing IR. No code yet; skeleton (#1) branches off `master` under
  Track A per the C-frontend precedent when work starts.
