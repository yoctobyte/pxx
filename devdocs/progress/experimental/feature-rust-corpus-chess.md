---
prio: 0
---
# Rust corpus: the own-written chess engine as Track R's real-world target

## STATUS (2026-07-16)

**Adapted-branch engine: DONE and bit-comparable by perft.** A pxx-friendly
branch of the movegen/search compiles and runs, and its move enumeration is
*identical to the reference perft* — the "bit-comparable" bar for a chess
engine. Two forms live in `test/`:
- `test_rust_chess_engine.rs` — faithful struct model (real `Move` struct in a
  `[Move; 256]` list passed as `&[Move]`), make/unmake, negamax, UCI output.
  perft(4)=197281 exact; picks the mate-in-1 `a1a8`.
- `test_rust_chess_perft_full.rs` / `test_rust_chess_search.rs` — packed-i64
  form: perft exact to depth 5 in `make test` (depth 6 = 119060324 confirmed
  locally), forced mate-in-1 and mate-in-2 found and depth-sensitive.

Frontend enablers landed to get here (all green, self-host byte-identical):
5/6-param internal calls (r8/r9 spill), fixed arrays of structs (`arr[i].field`),
slice-of-record (`&[Move]`, `slice[i].field`).

**NOT done: the UNMODIFIED `~/nextlevel/engine/src` sources.** Those remain
blocked on value-flow features the adapted branch sidesteps — in priority order
as the real modules hit them: ~~`Option<T>` (chess.rs wall, stage 2)~~ **DONE
2026-08-29**, ~~array-typed STRUCT FIELDS (`squares: [Piece; 64]`)~~ **DONE
2026-08-29**, ~~array-typed return values (`fn -> [T; N]`, attacks.rs)~~ **DONE
2026-08-29**, ~~`if` as an EXPRESSION (`let x = if c { a } else { b };` — not on
the original list)~~ **DONE 2026-08-29**, ~~the unity build for data
modules (tables.rs, stage 3)~~ **DONE 2026-08-29**, ~~`Result`/`?`~~ **DONE
2026-08-29**, then `String`/`format!`, derives/traits.
Do NOT claim the real source compiles — only the adapted branch does.

**Note on where the engine sources live:** they are NOT on the `frank-rust`
box (`~/nextlevel` does not exist here), so stage-2 work was driven from the
gap list above and from the shapes the real modules are written in, not from
re-probing the source. Re-probe before claiming a rung against the real files.

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
- 2026-07-16 — **ENGINE milestone + slice-of-struct enabler** (Track R / A).
  test/test_rust_chess_engine.rs: a faithful struct-based branch of the engine
  using the REAL data model — a `Move { from, to, flags }` struct held in a
  `[Move; 256]` list, passed between fns as `&[Move]` — instead of the packed
  i64 of the perft/search ports. make/unmake, negamax, material eval, and UCI
  best-move formatting via `as u8 as char`. Verifies end to end: perft(4) =
  197281 (movegen through the struct move list) and bestmove a1a8 (search picks
  the mate-in-1 rook lift and prints it in UCI). Enabler landed to get here:
  **slice-of-record** — `&[Move]` params, `&arr[lo..hi]` over a record array,
  and `slice[i].field` read/write. RSliceClassForRec now tracks the element
  recid (RSliceElemRec) alongside the elem tk; the slice-index lowering strides
  by RecSize and stamps the element recid on the AN_DEREF (ResolveNodeRec reads
  ASTIVal>0 there), so `slice[i].field` builds AN_FIELD over the deref with no
  shared-codegen change. Guarded the RTypeKindFromName-then-LastTypeRecId
  sequencing (side effect) against Pascal arg-eval-order at both param sites.
  Scalar `&[i64]` slices unchanged (perft/advanced regressions green); rust
  sweep + quick tier green; self-host byte-identical. The engine now mirrors
  the real chess.rs shape closely enough that the remaining gap to the actual
  source is the value-flow features (Option/Result/? and String/format!), not
  the board/movegen/search skeleton.

- 2026-08-29 — **STAGE 2 DONE: `Option<T>`** (Track R, the ~48h R window).
  Monomorphized onto the enum machinery that already existed: one
  auto-registered tagged-union UClass per concrete `T`, the same layout
  `RRegisterEnums` builds for a hand-written enum (`__tag` i64 at 0, payload
  as the mangled field `Some.0`), with `None`/`Some` pushed into
  `REnumVariants` so `match` needed no special case at all. Same shape as the
  borrowed-slice classes. **No new AST node, no new IR op, no shared-internals
  change** — nothing in this rung was a Track A edit. Three pushed units:
  1. the type + `Some`/`None` literals + `is_some`/`is_none`/`unwrap` + bare
     (unbraced) match arms. Monomorphization forces one design point: `Some`
     and `None` CANNOT resolve through the bare-variant table, because every
     instantiation spells its variants the same way — so the literal resolves
     against the EXPECTED type, or against the payload expression's own type
     when there is no annotation.
  2. Option through fn signatures — params and, the load-bearing half, RETURN
     values, free fn and impl method alike. This is where the real work was:
     struct/enum returns were rejected outright, and enabling them meant
     registering `ProcRetRecId`, allocating the hidden aggregate-destination
     local, and emitting `EmitAggregateDestStash` — without the last two,
     Result is written through a garbage pointer, **the identical segfault the
     C frontend hit on lua's by-value union return**, reproduced here and
     fixed by the same shared convention. Generalised: ANY record return works
     now, not just Option.
  3. the pattern half — `match` on an arbitrary expression (materialized once
     into a generated local), `if let PAT = e { } else { }`, `unwrap_or`. The
     scrutinee resolution, tag test and pattern binds were extracted out of
     `match` and shared, so `if let Rect { w, h } = s` over a user-declared
     enum works for free.
  Test `test/test_rust_option.rs`, in `make test`. Regressions green:
  perft_full exact through perft5 + kiwipete + promo, engine `bestmove a1a8`,
  search mates unchanged, self-host byte-identical at every unit.
  **Next rung found while testing:** an array-typed STRUCT FIELD
  (`struct Board { squares: [i64; 64] }`) is refused with `expected field
  type`. chess.rs's Board is a mailbox array, so that is the wall now, ahead
  of array-typed returns. Ticket: [[feature-rust-option-type]] carries the
  narrowings.

- 2026-08-29 — **stage-2 successors: rungs 4-8, all landed on `master`
  (`b3fd1c760` and after).** Array-typed struct fields (rung 4), `&`/`&mut`
  params that actually alias (rung 5 — the frontend was dropping the sigil, so
  `self.side = v` in a method silently did not reach the caller), aggregate
  literals in return position (rung 6), the engine's own idioms end to end
  (rung 7, `test_rust_engine_shapes.rs`), and **array-typed RETURN values plus
  `&[T; N]` params** (rung 8, `test_rust_array_return.rs`).

  **No Track A ticket was needed for any of the five.** Four times the shared
  machinery already had the mechanism and the Rust frontend had simply never
  reached for it — the NRVO hidden destination for record returns,
  `ProcParamExplicitByRef` for aliasing, `ProcRetFixedArrBytes` for array
  returns, and `IR_COPY_REC` from a call at the caller. That is the ladder
  earning its keep: driving from what the engine uses keeps finding gaps in the
  FRONTEND, where they are cheap, instead of in the IR.

  Rung 8 also surfaced a silent wrong-value bug that had nothing to do with
  arrays: **integer-literal suffixes were lexed and discarded**, so every
  literal was i32 and `1u64 << 44` evaluated to 0. It was found because a
  knight-attack table came back with 48 of 64 squares occupied — a plausible
  number. A bitboard engine is made of that expression, so this would have
  poisoned every table in attacks.rs.

  **New first wall, not on the original gap list:** `if` as an EXPRESSION
  (`let df: i64 = if k < 4 { 1 } else { 2 };`). Real Rust uses it constantly
  and the rung-8 probe had to be rewritten around it.

- 2026-08-29 — rung 9: `if` as an EXPRESSION, both the `let x = if ...` form
  and the tail form, lowered to the shared AN_TERNARY. Fifth consecutive rung
  needing no Track A change. The wall it named a few hours earlier is closed;
  **stage 3 (the unity build for data modules) is now the next item on the
  original gap list.**

- 2026-08-29 — rung 10: **the stage-0 trivia sweep is finally real rather than
  a swallow.** `[pub] type Alias = Target;` now aliases (resolved in
  RTypeNameAt, the one canonical type-name reader, so nothing downstream needs
  alias knowledge), and top-level `const NAME: [T; N] = [...]` registers a
  global filled at startup instead of being skipped whole. Those two are
  exactly what the 2026-07-09 baseline note meant by *"every module dies within
  its first 4 lines"*: `pub type Bitboard = u64;` names a bitboard engine's
  central type, and the attack tables ARE const arrays.

  Deviation stated rather than hidden: a const array is a mutable global here,
  not `.rodata`. No compiling program can observe it, and real `.rodata`
  initializers are Track A work that would buy the engine nothing.

  `test_rust_module_items.rs`. Stage 3's remaining half is the mechanical part
  — a `runner.rs` concatenation, the zlib trick — now that the items a
  concatenation produces all parse.

- 2026-08-29 — **an FPC-seed break landed and was caught by frankwasm, not by
  any gate.** `RExprRecId` was called above its declaration with no `forward`;
  pxx resolves across the unit, FPC resolves in source order, so the compiler
  self-hosted byte-identically while `compiler.pas` would not compile under FPC
  at all. The per-fix loop cannot see this class by construction — it compiles
  the compiler with pxx. `python3 tools/forwardlint.py` catches it and nothing
  invoked it. Fixed, both duplicate p80 tickets resolved, and forwardlint is
  now part of this lane's pre-push routine.

- 2026-08-29 - **stage 3 done: the unity build compiles and runs.**
  `test/rust_unity/` is four modules with real cross-module references, and
  `cat` is the whole build step - the zlib-runner trick, as planned. What
  concatenation does NOT fix is the module qualifiers, and that is the part the
  frontend supplies: `RStripTopItems` collects the crate root's `mod x;`
  declarations in a first pass and strips `<mod>::` / `crate::` / `self::` /
  `super::` in a second, so `crate::attacks::popcount(...)` flattens while
  `Board::new` and `Color::White` survive. Telling those two apart by the `mod`
  declarations is exact; a rule about capitalisation would not have been.

  **Stated limit: there is no rustc on this box**, so the corpus is a
  real-crate-SHAPED fixture, not a conformance one. It has not been checked
  against rustc and the Makefile comment says so.

  Stages 0-3 of the staged plan are now complete. Next on the original list:
  `Result`/`?`, `String`/`format!`, derives/traits - and the ArrayVec
  replacement (stage 4), which is corpus work rather than frontend work.

- 2026-08-29 - rung 12: **`Result<T, E>` and `?`.** Result monomorphizes onto
  the same enum machinery as Option, so `match` / `return Ok(..)` / field
  access worked the moment the class existed and the type reader learned two
  parameters. `?` desugars to the reference's own `match e ... Err(e) => return
  Err(e)`, with the operand materialization and the early return hoisted out of
  the expression (neither fits in an expression node) and flushed at a single
  point in RParseStatement. A `?` in a `while` condition is REFUSED rather than
  hoisted out of the loop.

  **The rung's real find is a bug in Option, not in Result.** A monomorphized
  payload was sized with `TypeSize`, which answers 8 for a record and says so
  in its own comment in symtab.inc. Option has had this wrong since it was
  written and got away with it because `Option<Square>` is exactly 8 bytes.
  Measured against master's rparser: `Option<Big>` (32 bytes) **segfaulted**,
  and `Result<Pos, i64>` read `Pos { file: 4, rank: 2 }` back as `4 0`. Fixed
  for both through one payload-size/align pair; both cases pinned.

  Second time this window that adding a feature surfaced a latent bug in the
  feature beside it, and both times the tell was a plausible value rather than
  an absent one.

  Remaining on the original gap list: `String`/`format!`, derives/traits, and
  the ArrayVec replacement (corpus work, not frontend work).

- 2026-08-29 - rung 14: **`String`, `&str`, `format!`.** The last value-flow
  item. Both Rust string types map to one managed AnsiString; the divergence is
  unobservable because telling them apart needs aliasing rustc's borrow checker
  refuses to compile, so the frontend supplies spelling and the shared ARC
  lowering supplies everything else.

  **The real work was the DRIVER, and the previous rung had already pointed at
  it.** `wantAnsiRuntime` was False here forever, with a comment calling the
  runtime "dead weight rather than a step it is missing" -- half right: turning
  it on alone fails with `unresolved forward: PXXStrFromLit`, because the shims
  are emitted machine code and their bodies live in builtinheap, with StrInt in
  builtin. Both units, or neither. Gated on a token scan, since the pair takes
  a hello-world from 2KB to ~62KB; the tell that separates a `println!` format
  literal (no runtime) from a literal used as a value (runtime) is its POSITION.

  **Third latent bug this window, third time the tell was a plausible value.**
  Rust procs never called EmitManagedLocalsZeroInit, so a managed local's first
  assignment released stale stack bytes. A two-`push` function returned the
  right answer alone and segfaulted once its caller held a string local of its
  own. Identical to bug-nilpy-string-local-truncates-at-255; the shared helper
  existed and this frontend had never called it.

  Also fixed: a char literal was a bare tkInteger, so `println!("{}", 'x')`
  printed 120. It now carries `char` in the same SVal channel an integer suffix
  uses -- no new token kind, so no Track A change.

  Remaining: derives/traits, and the ArrayVec replacement (corpus work).

