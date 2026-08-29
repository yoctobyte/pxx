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
2. `Option<T>` in fn signatures — params and, the load-bearing half,
   RETURN values. Struct/enum returns are currently rejected outright
   (`RTypeKindFromName(..., allowStruct=False)` on the return type), and
   `fn piece_at(..) -> Option<Piece>` is exactly that. Likely the largest
   unit of the three.
3. `if let Some(x) = e`, `match` on an arbitrary expression (today the
   scrutinee must be a plain local), and `unwrap_or`.

## Known narrowings (documented, not silent)

- `unwrap()` does not panic on `None` — it reads the payload slot as-is.
  This frontend has no panic path yet; a checked unwrap follows one.
- `Option<Option<T>>` is refused with a clear error: the `>>` lexes as a
  shift token, and splitting it is not worth doing before something needs it.
- `let x = None;` with no annotation is an error — nothing to infer from.

## Log
- 2026-08-29 — unit 1 landed (see the ladder ticket's log for the detail).
