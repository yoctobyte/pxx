# `for x in ...` iteration — FPC-exact (arrays, sets, strings, enums, enumerators)

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

## Decision (2026-06-17) — clone FPC's for-in surface exactly

Design locked after review: implement **exactly what FPC/Delphi do**, no
invented protocol, no new grammar. FPC's for-in compiles unmodified → the
Lazarus-compat line ([[project_gtk_gui_arc]]) holds. Dialect extensions
(two-var `for k, v in`, reverse, index-pair) are explicitly **deferred** — add
later only when needed, never as v1 divergence.

### The protocol is FPC's structural enumerator — NOT a custom contract

`for X in C do` resolves in this fixed order:

1. **Native** — C is array / set / string / enum-type → compiler emits the loop
   directly from known layout. No method lookup.
2. **Structural enumerator** — C has a method `GetEnumerator` returning E, where
   E has `function MoveNext: Boolean` and a readable `Current` member. **Pure
   duck-typing on those three names** — no base class, no `TCollection`, no
   interface required. (My earlier TCollection mention was misleading; FPC does
   NOT require any hierarchy.)

Hardcoding the three identifier names (`GetEnumerator` / `MoveNext` / `Current`)
in the compiler is accepted as fair — it is the FPC contract verbatim.

### Exact desugar (matches FPC manual)

```pascal
for X in C do Body;
```
≡
```pascal
__e := C.GetEnumerator;
try
  while __e.MoveNext do begin
    X := __e.Current;     { Current may be property (getter) or field }
    Body;
  end;
finally
  __e.Free;               { ONLY when E descends TObject; record E = no free }
end;
```

### Generator = one enumerator implementer

The shipped stackless generator ([[project_next_arc_concurrency]]) folds in:
`GetEnumerator` may return a generator; `MoveNext` = resume, `Current` = last
yield. The existing generator for-in special-case becomes one path under this
umbrella — same win generators already proved.

## Sources to cover — exactly FPC's set (each a side-case study)

**Native tier** (compiler knows layout, no GetEnumerator):

- **Static arrays** `array[lo..hi] of T` — element by value; bounds known at
  compile time. (Index variant out of scope — FPC has none.)
- **Dynamic arrays** `array of T` — Length-driven; element type T (incl. managed
  elements → refcount per element?).
- **Open-array params** `const xs: array of T` — Length already tracked.
- **Strings** — iterate Char by Char (`for c in s`). AnsiString vs frozen.
- **Sets** — iterate present members in ordinal order (32-byte bitset scan).
- **Enum type** — `for d in TWeekday do` iterates ALL enum values low..high
  (iterating the *type*, not a var). FPC supports this; include it.

**Structural tier** (GetEnumerator):

- **Collections** (lib/rtl/collections.pas: lists/maps) — via GetEnumerator. A
  TList yields elements. A TDictionary yields a **single** `TPair` record per
  iteration (you read `.Key`/`.Value` yourself) — FPC gives one loop var,
  never an unpacked pair. No special compiler handling: it's just an element
  whose type happens to be a record.
- **Generators** — fold in as one GetEnumerator implementer.

**Deferred (NOT v1 — dialect extension later):**

- Two-var `for k, v in map` unpacking — FPC has no such form. Trivial to add as
  `(index, value)` sugar later via a pair, but explicitly out of v1 scope.
- Reverse / step / filtered iteration — no FPC equivalent; defer.
- `operator Enumerator` global overload (bolt for-in onto types you don't own) —
  FPC supports it (ObjFPC mode); lowest priority, optional later slice.

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

## Approach — sliced

- **Slice A — native for-in.** dynarray → static array → open-array → string →
  set → enum-type. Compiler emits loop from known layout. Each its own commit +
  test (`test_forin_native.pas`). No library dependency. Lands first.
- **Slice B — structural enumerator desugar.** Compiler recognises
  `GetEnumerator`/`MoveNext`/`Current` (duck-typed), emits the desugar above
  (incl. `try..finally __e.Free` only when E descends TObject). Support both
  class and record enumerators; `Current` as property OR field via existing
  member lookup. Fixture `test_forin_enumerator.pas` defines a TIntList +
  enumerator, iterates, asserts.
- **Slice C — generator bridge.** Route the existing generator for-in special-
  case through GetEnumerator-shaped resolution so it's uniform. Fixture
  `test_forin_generator.pas`.
- **(deferred slices)** two-var key/value sugar; `operator Enumerator` overload.

Library-first: array/string/set iteration is compiler-native (Slice A);
collection enumerators live in lib/rtl. `for-in` lowering in the compiler stays
minimal and shared (pre-codegen) so all targets get it free.

## Acceptance

`for x in <static-array|dynarray|open-array|string|set|enum-type>` yields the
right value sequence with correct element typing (Slice A). `for x in <object
with GetEnumerator>` desugars correctly incl. enumerator lifetime (Slice B).
Generator for-in routes through the same path (Slice C). A representative FPC
for-in program compiles **unmodified**. Self-host fixedpoint + cross-bootstrap
byte-identical (run `make cross-bootstrap` — the generator work proved x86-64
fixedpoint alone misses cross regressions).

## Log
- 2026-06-16 — opened, split out of feature-generators-yield. Generators need
  nothing from this; it is additive `for-in` breadth.
- 2026-06-17 — design review with user. Locked: clone FPC's for-in surface
  EXACTLY (structural `GetEnumerator`/`MoveNext`/`Current` duck-typing, no
  invented protocol, no new grammar). Earlier TCollection framing corrected —
  FPC requires no hierarchy. Two-var `for k,v in` + operator-Enumerator deferred
  to later dialect slices. Sliced A (native) / B (enumerator) / C (generator
  bridge). Goal = unmodified FPC for-in compiles.
