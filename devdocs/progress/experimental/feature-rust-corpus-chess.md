---
prio: 0
---
# Rust corpus: the own-written chess engine as Track R's real-world target

- **Type:** feature — corpus / north star for Track R (X-tagged: zero prio,
  experimental; work it on user request or for fun)
- **Opened:** 2026-07-09 (user decision: "we have a real-world own-written
  test target — chess engine written in rust")
- **Target:** `~/nextlevel/engine` — 5.9k lines, 14 modules, idiomatic
  Rust (ArrayVec, derives, Option, &str, tuple structs, traits, modules).
  OWN-WRITTEN, which changes the rules vs foreign corpus (zlib/tcc): we
  may adapt the target too — e.g. a pxx-friendly branch swapping the
  `arrayvec` crate for a local fixed-array+len module is fair game, the
  way a foreign corpus never is.

## Why this target is ideal

- **Perft is a built-in oracle.** Chess move generation has `perft(depth)`
  — one number, brutally sensitive to any miscompile, diffable against
  `cargo build` output. Better than zlib's byte-diff: it exercises deep
  branching logic, not just data plumbing.
- It drives every open Track R ticket with a concrete need instead of
  spec-completeness: the gap list below IS the remaining experimental
  Rust tickets, now ordered by what the engine actually uses.

## Baseline (2026-07-09, rparser as of the ports-back pass)

Every module dies within its first 4 lines: `use` items unhandled,
`#[derive(...)]`/`#[inline]` attributes unhandled, top-level `const X:
usize = ...` items unhandled, `pub type` aliases unhandled. So stage 0 is
pure swallowing/trivia, cheap and high-leverage.

## Staged plan (each stage = more of the engine parses/compiles)

0. **Trivia sweep (cheap):** swallow `use ...;`, `#[...]`/`#![...]`,
   `//!` docs; `pub type Alias = ...;`; top-level `const NAME: T = expr;`
   including const arrays (`[T; N]` literals already landed at let-level).
1. **Core-language pass (single file):** tuple structs (`Square(pub u8)`),
   `Self` in impls, method calls with by-value self returning Self,
   `match` on `Self::Variant` paths, u8/i8 arithmetic with `as` casts,
   `wrapping_add/sub/shr` mapped to plain ops (documented deviation).
2. **Option + str (drives [[feature-rust-rtl-core-types]] and the &str
   half of [[feature-rust-borrowed-slice-type]]):** `Option<T>` as a
   monomorphized generic enum (concrete enums + generic fns both exist;
   generic ENUM instantiation is the new piece), `&str` as the landed
   ptr+len slice with `.len()`/`.as_bytes()`/byte indexing.
3. **Modules via unity build (kills the multi-file problem the zlib way):**
   a `runner.rs` concatenation (or a tiny preprocessor step stripping
   `use crate::...` and `mod x;`) — no real module system needed, same
   trick as test/zlib/runner.c.
4. **ArrayVec replacement:** pxx-friendly engine branch with a local
   `struct MoveList { data: [Move; 256], len: usize }` — allowed because
   the target is ours.
5. **Traits/derives as used** ([[feature-rust-derive-macros]],
   [[feature-rust-dyn-trait-dispatch]]): the engine mostly needs
   `PartialEq`/`Clone`/`Copy` derives (field-wise synthesis) and
   `fmt::Display` for UCI output — the latter may be cheaper rerouted
   through println!-style intrinsics than through real trait dispatch.
6. **Gate ladder:** all files parse → chess.rs compiles → `perft(4)`
   matches cargo → search finds a mate-in-2 → uci.rs echo loop.

## Non-goals

- No cargo, no crates.io — arrayvec is the only external dep and it gets
  replaced, not ported.
- No iterator-protocol machinery unless the engine's hot paths demand it;
  adapting a `.iter()` loop to indexed `for i in 0..n` in our own source
  is cheaper than building iterators (documented per-site when done).
- Syzygy/polyglot-book modules last or never (file I/O breadth).

## Log
- 2026-07-09 — filed with baseline probe results; stage 0 unstarted.
- 2026-07-09 — **stage 0 DONE** (same session): #[...]/#![...] attributes
  swallowed in rlexer; RStripTopItems compacts the token stream before
  every prescan (use/mod items, [pub] type aliases, `pub` at any depth);
  top-level scalar `const NAME: T = lit;` registered via AddConst, const
  arrays swallowed whole; i8/i16/u8/u16 added to the type map; prescan
  order fixed to shells -> enums -> struct fields (enum-typed struct
  fields resolve now). Probe after: every module fails on a REAL ladder
  gap — chess.rs on Option (stage 2), eval.rs on associated fns (no-self
  impl fns), search.rs on cross-module Move (stage 3 unity), attacks.rs
  on const-fn array builders (stage 2/adapt), uci.rs on Arc (adapt).
  Regressions green (rust tests, quick tier, fixedpoint).
