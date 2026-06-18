# `is` / `as` / `Supports` — runtime class type-tests

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (extracted from feature-interfaces item 5 — useful on its own)

## Motivation

`obj is TFoo` and `obj as TFoo` are **not implemented even for plain classes**
today (`if a is TB` → `Expected: then, but got: is`). They are the natural
downcast/type-test surface for any OO code (and the demos). Extracted from
feature-interfaces (which needs the same runtime type-walk for its `Supports`)
because it is independently valuable and much smaller than the full interface
arc — and it pre-builds that arc's item 5.

## What exists to build on

- **RTTI class registry** (name / parent / instSize / vmt) is already emitted
  per class — the parent chain needed for the type-walk is present.
- VMT layout + `IR_VIRTUAL_CALL` dispatch are done.

The only genuinely new piece is the **runtime type-walk**: given an instance's
class RTTI pointer, walk the parent chain looking for the target class RTTI.

## Mechanism

1. **Distinct AST nodes.** `X is T` → `AN_IS_TEST`, `X as T` → `AN_AS_CAST`.
   Resolve in the **parser** by context+type and tag the node — do **not** fold
   into another operator or key behaviour off a global flag (see the and/or
   history: bitwise-vs-logical broke when keyed off a global; the fix was to
   decide per-node in the parser. `as` is currently a contextual ident, not a
   reserved token — keep the cast-expression use cleanly separate from
   `specialize ... as Name`).
2. **`is`** → load the instance's class-RTTI pointer, walk `parent` links; result
   Boolean (True if target found, False on nil or no match).
3. **`as`** → same walk; on match yield the (same-pointer) instance typed as T;
   on mismatch raise an invalid-cast error (or, until the exception class exists,
   a clear runtime trap). nil `as T` = nil.
4. **`Supports`** (function form) — same walk, Boolean result; shares the helper.

Emit the walk as a small runtime helper (one per program, like the other
managed helpers), called from `AN_IS_TEST` / `AN_AS_CAST` codegen, so all
targets share one implementation.

## Scope boundaries

- Classes only here. Interface `is`/`as`/`Supports` (querying an interface) is
  feature-interfaces, which reuses this walk.
- No metaclass (`TClass`) `is`/`as` beyond what the registry already gives.

## Acceptance

- `obj is TDerived` / `obj is TBase` / `nil is T` give correct Booleans across a
  small inheritance tree.
- `obj as TDerived` succeeds on a real derived instance, traps on a bad cast,
  passes nil through.
- Covered by an oracle test on all four Linux targets; `make test` green;
  cross-bootstrap byte-identical.
