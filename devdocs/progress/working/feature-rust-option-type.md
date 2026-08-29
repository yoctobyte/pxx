---
prio: 0
track: R
---
# Rust frontend: `Option<T>` — the stage-2 rung of the chess ladder

- **Type:** feature — Track R (X-tagged: experimental, unranked; picked up on
  the user's 2026-08-29 request to run Track R for a ~48h window)
- **Status:** working
- **Owner:** Claude (~/frank-rust)
- **Opened:** 2026-08-29
- **Umbrella:** [[feature-rust-frontend]] · ladder: [[feature-rust-corpus-chess]]

## Why this rung

[[feature-rust-corpus-chess]] names the gap list in the order the real engine
modules hit it, and `Option<T>` is first: *"chess.rs wall, stage 2"*. The
adapted branch sidesteps it (packed i64 / sentinel squares); the UNMODIFIED
`~/nextlevel/engine/src` cannot — `piece_at() -> Option<Piece>` and
`ep_square: Option<Square>` are the shape the source is written in.

Not spec-completeness: `Option` is picked because the engine uses it, per the
umbrella's *"pick work from its ladder"* instruction.

## Approach — monomorphize onto the enum machinery that already exists

No new AST node, no new IR op, no shared-internals change: one auto-registered
tagged-union UClass per concrete `T`, exactly the layout `RRegisterEnums`
gives a hand-written enum (`__tag` i64 at 0, payload as the mangled field
`Some.0` past it), with `None`/`Some` pushed into `REnumVariants` so `match`
resolves arm names against the scrutinee's own class with no special case.
Same shape as the borrowed-slice `&[T]` classes (`RSliceClassForRec`).

The one thing monomorphization forces: **`Some`/`None` cannot go through the
bare-variant table.** Every instantiation declares variants spelled `Some` and
`None`, so that lookup is ambiguous the moment a second `T` appears. The
literal is therefore resolved against the EXPECTED type (the annotation), or,
when there is none, against the payload expression's own type.

## Units (pushed separately)

1. **DONE** — the type, the literal, the accessors, bare match arms.
   `let x: Option<T>` annotations (via a new `RTypeNameAt`/`RTypeNameCur`
   that reads a generic type at any type site), `Some(e)`/`None` literals
   with expected-type or inferred resolution, `is_some`/`is_none`/`unwrap`
   as pure field reads, and unbraced match arms (`Some(v) => f(v),` — the
   spelling real source uses; the block form was the only one accepted).
   Test `test/test_rust_option.rs`, in `make test`.
2. **DONE** — `Option<T>` in fn signatures: params and, the load-bearing
   half, RETURN values, on a free fn and an impl method alike. Struct/enum
   returns were rejected outright; allowing them turned out to be pure
   frontend wiring — the shared machinery has always compiled a
   record-returning routine (Pascal's `function F: TRec`), the Rust
   frontend simply never registered `ProcRetRecId`, never allocated the
   hidden aggregate-destination slot, and never emitted
   `EmitAggregateDestStash`. Without the last two, Result is written
   through a garbage pointer — the identical segfault the C frontend hit
   on lua's by-value union return, reproduced here and fixed the same way.
   Generalised rather than special-cased: any record return works now, not
   just `Option<T>`. Impl-method params also gained struct/enum types
   (they were `allowStruct=False` while free fns were already `True`) and
   the `IsRef` flag a record param needs.
3. **DONE** — the pattern half. `match` now accepts an ARBITRARY
   expression as its scrutinee (`match self.piece_at(sq)`, the spelling
   real source uses), evaluated once into a generated local; `if let
   PAT = e { .. } else { .. }` lands as a one-arm match; `unwrap_or(d)`
   is a value select over the tag via the shared AN_TERNARY the C and Zig
   frontends already use. None of it is Option-specific — the scrutinee
   resolution, the tag test and the pattern binds were extracted out of
   `match` into `RParseScrutinee` / `RTagTest` / `RParsePatternBinds` and
   are shared, so `if let Rect { w, h } = s` over a user-declared enum
   works for free.

## Known narrowings (documented, not silent)

- `unwrap()` does not panic on `None` — it reads the payload slot as-is.
  This frontend has no panic path yet; a checked unwrap follows one.
- `Option<Option<T>>` is refused with a clear error: the `>>` lexes as a
  shift token, and splitting it is not worth doing before something needs it.
- `let x = None;` with no annotation is an error — nothing to infer from.
- A non-variable scrutinee must be a call or a plain variable: `RExprRecId`
  answers for `AN_CALL` and `AN_IDENT`, so `match self.some_field` (a
  record-typed FIELD) is not resolvable yet and says so.
- Option accessors work on any LVALUE receiver (variable, field, element)
  but not on a call result: `maybe(4).unwrap_or(-1)` is still refused, `let m
  = maybe(4); m.unwrap_or(-1)` works. Materializing a temp would lift it, the
  same fix the match scrutinee got.
- `println!` evaluates each argument as it reaches that placeholder, so a
  side-effecting argument interleaves with the format text — Rust evaluates
  all arguments first. Noticed while writing the tail-return test.
- Compound assignment on a field/index target names the target subtree on
  both sides, so a side-effecting subscript (`a[f()] += 1`) evaluates that
  subscript twice. A narrowing, not a wrong answer.
- **pxx brace comments NEST.** A `{` written inside a `{ ... }` comment
  opens a second one, and the comment then runs to the *next* `}` —
  which in this file was a `'}'` string 150 lines later, reported as
  `unexpected character` on an innocent blank line. Cost a build cycle;
  worth knowing before writing a comment that quotes Rust syntax.

## Rungs found by testing, past the Option stage

Both were discovered by writing engine-shaped code against the new
signatures, not from the ladder's list — and both are ahead of it now:

4. **DONE** — fixed-array STRUCT FIELDS (`squares: [i64; 64]`). chess.rs's
   Board is a mailbox array and the frontend refused the syntax outright.
   Frontend wiring: `UFldIsArray`/`UFldArrLen` already model an array field
   (Pascal's `array[0..N-1] of T` and C's `int a[N];` land on it), access is
   AN_INDEX over AN_FIELD, and `field[i].member` for a record element comes
   free from `ResolveNodeRec`'s existing arm. `test/test_rust_struct_array_field.rs`.
5. **DONE** — `&`/`&mut` parameters actually ALIAS. This was the serious one:
   the frontend DROPPED the `&` on a parameter, so the one bit that decides
   aliasing never reached `ProcParamExplicitByRef`, `ir.inc` read the by-ref
   flag as the silent >8-byte ABI promotion, and every record argument was a
   private temp copy. `self.side = v` in a method wrote into that copy and the
   caller saw nothing — **silently, no diagnostic**. `&mut self` was not even
   accepted by the parser. Measured, not reasoned: `PXXDBG=a.ir:main` showed
   the `IR_COPY_REC` into a temp at the call site.
   Fixed by recording `&` and setting `ProcParamExplicitByRef`, keeping the
   by-value copy for a plain `p: T` / `self` — the half a blanket
   "always alias" fix would have broken, and the half the test pins.
   Compound assignment on a field/index target (`self.n += 1`) rode along; it
   is how real code spells this mutation. `test/test_rust_refs.rs`.
6. **DONE** — value positions: a whole struct/enum RETURNED, and Rust's
   implicit TAIL return. `let` carried three near-copies of "parse an
   aggregate literal and store it into a slot" (enum variant, tuple struct,
   named-field); they are now ONE implementation
   (`RPeekAggregateCi` + `RParseAggregateInto`) that the `return` path uses
   too, so `return Square(i)` / `Point { .. }` / `Circle(r)` / `Some(x)` all
   work and the Option-specific return branch is gone. The tail return applies
   to a fn BODY and deliberately not to any inner block — an inner block's
   trailing expression is a block VALUE, and treating one as a return would
   turn `if c { f() }` into an early exit; `test_rust_value_positions.rs`
   pins that anti-case. `test/test_rust_value_positions.rs`.
7. **DONE** — the rest of the engine's own idioms, driven by writing
   `chess.rs`-shaped source and fixing what it hit, one wall at a time:
   nested aggregate literals and array initializers inside a struct literal
   (`Board { squares: [0; 64], ep: None, .. }`), an aggregate literal as an
   ASSIGNMENT rhs (`self.ep = Some(sq);`), a method on a record-typed FIELD
   (`self.side.flip()`), a tail `match` whose arms are the fn's return values
   (`fn flip(self) -> Color { match self { .. } }`), and the Option accessors
   on any lvalue receiver rather than only a plain variable (`b.ep.is_none()`).
   The literal parser now takes a target NODE instead of a symbol, which is
   what let `let` / `return` / field-assign / nested-field all share it.
   `test/test_rust_engine_shapes.rs` is the acceptance shape: every construct
   in it was refused at the start of this window.

8. **DONE** — fixed-array RETURN VALUES (`fn f() -> [T; N]`), the ladder's
   attacks.rs rung, plus the integer-literal suffix bug it surfaced.

   The ABI needed nothing: `ProcRetFixedArrBytes` + `ABIRetViaHiddenDestProc`
   have carried Pascal's `function F: TArr` since
   `bug-a-set-and-array-function-results-come-back-empty`, and the caller side
   (whole-array `IR_COPY_REC` from a call) was already in `ir.inc`. **Fourth
   rung running where the shared machinery had the mechanism and the Rust
   frontend had simply never reached for it.** What the frontend needed: parse
   `-> [T; N]` (one `RRetTypeAt`/`RRetTypeCur` pair replacing four hand-written
   return-type reads), record the shape at SIGNATURE time rather than body time
   (a call site is lowered while the CALLER's body is parsed, which can precede
   the callee's), allocate `Result` AS an array, and lower a value in return
   position through `RReturnValue`.

   That last one is where the measurement mattered. `return a;` lowered as
   AN_EXIT-with-a-value, which is a SCALAR store into Result: `PXXDBG=a.ir`
   showed `store_sym Result := lea(a)` where a 32-byte copy belongs. The caller
   then copied its 32 bytes perfectly faithfully, so `[0,1,4,9]` printed as a
   stack address and three zeros with no fault anywhere. Reasoning about it
   would have blamed the caller.

   Also landed here because the same test needed it: `&[T; N]` params (an array
   REFERENCE, which Rust distinguishes from the `&[T]` slice that shares the
   parse site) and unannotated `let t = f();` resolved from the callee's
   registered return shape, for a plain call and for a method through the
   receiver's class.

   **The integer-literal suffix was a silent wrong-value bug, not a gap.** The
   lexer consumed `u64`/`i64`/... and discarded it, so every literal was i32:
   `1u64 << 44` evaluated to **0** and `1u64 << 31` to `0xFFFFFFFF80000000`,
   neither with a diagnostic. Found because a knight-attack table came back
   with 48 of 64 squares empty — a plausible number, which is exactly the shape
   of bug this repo's debugging playbook is written about. Fixed by carrying
   the suffix on the raw token's `SOffset`/`SLen` (shared `Next` already
   surfaces that as `CurTok.SVal`, so no shared-struct change) and typing the
   literal through the existing name→kind mapper, a suffix being spelled
   exactly like the type name. An unsuffixed literal too big for i32 now widens
   to i64 rather than truncating.

   **Narrowings, deliberate and recorded rather than worked around:**
   - `let x = if c { a } else { b };` — `if` as an EXPRESSION is not parsed.
     Real Rust uses it constantly; it is the strongest candidate for the next
     rung.
   - `[Sq { .. }; N]` — an array literal whose element is a struct literal.
     Uninitialised `let mut c: [Sq; 2];` is the workaround in the test.
   - impl-method params take neither `&[T]` slices nor `&[T; N]` arrays; only
     free fns do. The impl registration path never had slices either, so this
     is a pre-existing symmetry gap, not one introduced here.
   - indexing a call result directly (`f()[0]`) is not parsed; Pascal has
     `ProcRetArrAi` for exactly that and the Rust side does not populate it.

## Log
- 2026-08-29 — unit 1 landed (see the ladder ticket's log for the detail).
- 2026-08-29 — unit 2 landed: Option (and records generally) through fn
  signatures and returns.
- 2026-08-29 — unit 3 landed: expression scrutinees, `if let`, `unwrap_or`.
- 2026-08-29 — rung 4 landed: fixed-array struct fields.
- 2026-08-29 — rung 5 landed: `&`/`&mut` params alias; `&mut self` parses;
  compound assignment on a field/index target.
- 2026-08-29 — rung 6 landed: aggregate literals in return position (one
  shared implementation with `let`), and implicit tail returns.
- 2026-08-29 — rung 7 landed: nested/array struct-literal fields, aggregate
  assignment rhs, methods on record fields, tail matches, Option accessors on
  any lvalue. `test_rust_engine_shapes.rs` compiles and runs.
- 2026-08-29 — merged `origin/master` into the topic branch at this rung
  boundary (the cadence the coordinator asked for), and converted this
  ticket's five Makefile assertions to `tools/expect_same.sh` so they are not
  new instances of the defect Track B spent the day removing.
- 2026-08-29 — merged `rust` into `master` at `b3fd1c760` (window opened by the
  coordinator; merged, not rebased, so the eight commits keep their shas).
- 2026-08-29 — rung 8 landed: fixed-array returns, `&[T; N]` params, and the
  integer-literal suffix fix. `test_rust_array_return.rs` is the acceptance
  shape; its knight-table oracle is hand-checked rather than recorded from a
  run, because the bug it pins produced *plausible* numbers.
