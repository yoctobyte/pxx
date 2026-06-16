# General `for x in ...` iteration (arrays, sets, collections, key-value)

- **Type:** feature
- **Status:** backlog
- **Opened:** 2026-06-16
- **Relation:** extends the `for-in` driver added for generators
  (feature-generators-yield). Generators do NOT depend on this — the current
  `for-in` parser special-cases a generator call and is self-contained. This
  ticket is purely additive: make `for x in <thing>` work over more sources.

## Why separate

The generator `for-in` is one fixed shape: `for x in Gen(args)` desugars to
`CoAlloc / while CoNext do x := CoCurrent / CoFree`. General iteration is a much
broader surface with many container shapes and edge cases, none of which
generators need. Keep it out of the concurrency arc.

## The unifying idea — one iterator protocol

`for-in` should drive an **iterator contract**, and each iterable provides an
implementation. A generator is just one implementer. Likely shape (decide
during design):

```
function MoveNext(var it): Boolean;   { advance; False when done }
function Current(const it): T;        { value at the cursor }
```

(or a single `function Next(var v: T): Boolean`). Implement the protocol +
`for-in` lowering ONCE; every source plugs in. `for-in` never cares which kind
of source it drove — same win generators already proved.

## Sources to cover (each is a side-case study)

- **Static arrays** `array[lo..hi] of T` — element by value; bounds known at
  compile time. Index variant `for i in Low(a)..High(a)`? (maybe out of scope)
- **Dynamic arrays** `array of T` — Length-driven; element type T (incl. managed
  elements → refcount per element?).
- **Strings** — iterate Char by Char (`for c in s`). AnsiString vs frozen.
- **Sets** — iterate present members in ordinal order (32-byte bitset scan).
- **Open-array params** `const xs: array of T` — Length already tracked.
- **Collections** (lib/rtl/collections.pas: lists/maps) — via the protocol; a
  TList yields elements, a TDictionary yields... what? (see key-value).
- **Key-value pairs** — `for kv in map` yielding a pair record, OR a
  `for k, v in map` two-variable form (grammar extension — decide).
- **Generators** — already done; fold into the protocol so it's uniform.

## Hard questions / side-cases to resolve in design

- **Element copy vs reference:** value semantics (copy each element into `x`) vs
  aliasing. Managed elements (AnsiString / dynarray / record-with-managed) need
  per-element retain/release if copied — ties into feature-zero-init-contract.
- **Mutation during iteration:** undefined? snapshot length up front?
- **Loop var typing:** `x`'s type must match the element type; today the
  generator path reads `Syms[varIdx].TypeKind`. Need element-type inference per
  source.
- **`for k, v in` grammar:** two loop vars for key-value — lexer/parser change,
  or sugar over a pair record.
- **Nested / break / continue / exit** inside `for-in` — must interop with the
  existing loop-control codegen.
- **Cross-target:** keep the lowering in shared IR / library so i386/arm32/
  aarch64/riscv32/xtensa all get it free (avoid the per-target-codegen +
  local-array landmines hit in the generator work).

## Approach sketch

1. Define the iterator protocol (record + 2 funcs, or a Next(var v)).
2. Refactor the generator `for-in` to route through it (generator = one impl).
3. Add impls incrementally: dynarray → static array → string → set → collections
   → key-value. Each its own commit + test.
4. Library-first: the protocol structs + array/string/set iterators live in
   lib/rtl (PXX-only where they exceed the FPC∩PXX subset); `for-in` lowering in
   the compiler stays minimal.

## Acceptance

`for x in <array|dynarray|string|set|collection>` yields the right sequence with
correct element typing; key-value iteration works in whatever form is chosen;
self-host fixedpoint + cross-bootstrap byte-identical (run `make cross-bootstrap`
— the generator work proved x86-64 fixedpoint alone misses cross regressions).

## Log
- 2026-06-16 — opened, split out of feature-generators-yield. Generators need
  nothing from this; it is additive `for-in` breadth.
