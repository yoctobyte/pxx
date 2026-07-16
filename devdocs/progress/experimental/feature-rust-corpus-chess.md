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
- 2026-07-09 — **PERFT MILESTONE: 20 / 400 / 8902 exact** (same session).
  test/test_rust_chess_perft.rs — a C-style port of the movegen core in
  the pxx subset (mailbox board + move lists as &[i64] slices through
  fns via the record ABI; no structs/Option/ArrayVec; no EP/castle/
  promotion, which first matter at ply >= 4). Wired into make test;
  runs in ~20ms. Enablers landed this session: bit-op expression layer +
  as-casts + compound assigns; &/&mut borrow no-ops; &[T]/&mut [T]
  slice parameters (prescan + body); Rust integer `/` -> tkDiv. That
  last one CASHED IN the Zig probe's prophecy: rparser mapped `/` to
  tkSlash (Pascal real division), latent because no Rust test ever
  divided — rank_of's sq/8 returned the bit pattern of 1.0. Also fixed
  a second latent paramless-recursion bug (RParseUnary self-call read
  the Result alias). Next rungs toward the REAL engine sources: tuple
  structs, associated fns + Self, Option, struct array fields, static
  tables, intrinsic u64 methods.
- 2026-07-09 — tuple structs landed (declaration/prescan, `Name(args)`
  let-constructor, `.0` field access) — and their FIRST multi-struct test
  found a shared symtab bug: UClass field windows go stale under
  shells-then-fields registration (any 2+ field-bearing structs; latent
  for named structs since the skeleton). Filed as Track A ticket
  [[bug-uclass-field-window-stale-base]] with root cause + one-line fix,
  NOT worked around (experimental-frontends rule). That ticket now BLOCKS
  every multi-struct rung of this ladder (chess.rs declares ~6 structs);
  unblocked rungs continue meanwhile (associated fns/Self, Option,
  intrinsics, statics).

- 2026-07-15 — **FULL-LEGALITY PERFT MILESTONE** (Track R, A+B+C+P held).
  test/test_rust_chess_perft_full.rs extends the depth-3 port to complete
  chess rules — en passant, castling (path-attack + emptiness checks),
  promotion + underpromotion, check filtering with make/unmake. Node counts
  match the standard reference perft EXACTLY:
    startpos  1=20 2=400 3=8902 4=197281 5=4865609
    CPW promo (n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b)  1=24 2=496 3=9483
  i.e. the movegen enumerates identically to the reference implementation
  (the "bit-comparable" bar for a chess engine = identical move sets).
  Move packed into one i64 (from | to<<6 | flags<<12) + castling-bitmask/ep
  threaded by value stands in for the engine's `Move` struct + ArrayVec<Move,
  256> — the ticket's sanctioned local-structure replacement. Board stays a
  signed-i64 mailbox (documented deviation from the engine's u8 encoding).
  Enabler landed (Track A file, self-resolved under combined assignment):
  **5th/6th internal-call params were miscompiled.** The Rust frontend's two
  bespoke param-register spill loops (RParseTopLevelFn, RParseTopLevelImpl)
  had a `case i of 0..3` that emitted NOTHING for param index 4/5 — so `mov
  [rbp+off], r8` came out as `48 89 <off32>` (REX+opcode, no modrm), a bad
  instruction stream that SIGILL'd at the 5th param. Extracted one
  REmitParamRegSpill helper that computes REX.R for r8/r9; param cap set to 6
  (register-convention max) with a clear over-limit error. Shared prologue in
  parser.inc was always correct (Pascal 5-param works) — this was
  Rust-frontend-only. Regressions green: quick tier, all test_rust_*.rs
  compile, else_if=20, self-host byte-identical. Next real-source rungs
  unchanged: Option (stage 2), unity build (stage 3), then perft on the
  ACTUAL chess.rs sources vs cargo.
- 2026-07-16 — **SEARCH MILESTONE + perft(6) confirmed** (Track R).
  test/test_rust_chess_search.rs: material-eval negamax with mate scoring on
  the same movegen (MATE=1000000, nearer mates score higher via a ply term).
  Finds a forced mate-in-1 (depth 2, score 999999) and mate-in-2 (depth 4,
  score 999997 = MATE-3), and does NOT see either one ply shallower — so mate
  detection is genuine minimax depth, not a static-eval artifact; symmetric
  start-position eval = 0. This clears the stage-6 "search finds a mate" rung.
  Note on the scheme: a delivered-mate node is only recognised when it still
  GENERATES moves (depth >= 1), so detecting mate-in-N needs search depth 2N.
  Also confirmed perft(6) from startpos = 119060324 (exact reference; 119M
  nodes, ~60s single-threaded) — the strongest single-position movegen check,
  left out of `make test` for runtime. No compiler change this round (the
  5/6-param fix from the previous entry was the only frontend edit); pure
  new-corpus + Makefile. Remaining ladder toward the ACTUAL engine sources is
  unchanged: Option (stage 2), unity build (stage 3), then perft/search on the
  real chess.rs/search.rs vs cargo.
- 2026-07-16 — **struct-array enabler** (Track R / A shared). Fixed arrays of a
  struct or tuple-struct type with per-element field access: `let mut list:
  [Move; N];`, `list[i].field = e` / `= list[i].field`, and tuple `list[i].0`.
  Rides the shared array-of-record codegen — AllocArray already sizes record
  elements via LastTypeRecId/ElemRecName, and ResolveNodeRec(AN_INDEX) already
  yields the element record, so the frontend only had to (a) accept a struct
  element type in the `[T; N]` annotation, (b) set LastTypeRecId before the
  no-init AllocArray, (c) parse `arr[i].field` into AN_FIELD(AN_INDEX) in the
  expression path, (d) accept AN_FIELD as an assign target. No shared-codegen
  change. This is the [Move; 256] move-list stand-in for the engine's
  ArrayVec<Move, 256> — the last piece needed to rebuild the movegen with the
  engine's real Move/Square STRUCTS instead of the i64 packing. test/
  test_rust_struct_array.rs; regressions green (rust sweep, quick tier,
  self-host byte-identical). Deliberate narrowing: whole-element store
  `list[i] = some_move` (record-value copy) not yet wired — the movegen writes
  fields individually; pxx also does not enforce Rust definite-init, so the
  arrays are annotation-only `let` then filled.
