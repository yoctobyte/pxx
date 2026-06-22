# Record copy with a dynamic-array field: PXX deep-copies, FPC shares (reference)

- **Type:** design question (semantics) — **Track A**, needs a decision
- **Status:** backlog — **decision needed before any code change**
- **Opened:** 2026-06-22
- **Found by:** Track A, dynarray-aggregate FPC-vs-PXX probe.

## The divergence

```pascal
type TR = record n: Integer; a: array of Integer; end;
var x, y: TR;
...
y := x;          { whole-record copy; record has a dynamic-array field }
y.a[0] := 99;
```

| compiler | `x.a[0]` after | meaning |
|----------|----------------|---------|
| FPC (`-Mobjfpc`) | `99` | the dyn-array field is a **reference** — the copy SHARES the handle (refcount++), COW only on `SetLength`/`Unique` |
| PXX (current) | `1`  | the dyn-array field is **deep-copied** — `y.a` is independent data (value semantics) |

Both run; no crash. It is a **silent semantic difference**, not a bug per se.

## Why it matters

FPC dynamic arrays are reference types; idiomatic FPC/Delphi code can rely on
the sharing (pass a record around, mutate the shared array, see it everywhere;
or rely on cheap O(1) record copies). PXX's deep copy is arguably *safer* and
more intuitive (true value semantics, no aliasing surprises) but diverges from
FPC, so a ported library that assumes sharing would behave differently — and the
divergence is invisible until a mutation-through-an-alias is observed.

## Options

- **(a) Match FPC — reference semantics.** Record copy / `var`-param store /
  by-value return SHARE the dyn-array field handle and refcount it (retain on
  copy, release on scope exit, COW in `SetLength`/`Unique`). Most FPC-faithful;
  the biggest change (touches IR_COPY_REC[_MANAGED], the field-store path that was
  just made handle-correct, and dyn-array refcounting through aggregates). The
  managed-string record work (feature-cross-managed-aggregates) is the template.
- **(b) Keep PXX value semantics, document it.** Cheaper, safer-by-default, but a
  standing FPC-compat caveat for Track B ports. Pair with a deep-copy guarantee
  for managed *element* types (so a deep copy of `array of AnsiString` copies the
  strings too — verify current behaviour).
- **(c) Hybrid — not recommended.** Per-type opt-in is more surface than value.

Note: the recently-fixed handle store (`bug-dynarray-in-record-corrupt`, commit
39d851a) deliberately used **share semantics for the field STORE** (no
retain/release) — that is consistent with (a)'s direction at the store site but
without the refcount; choosing (a) would complete it, choosing (b) would instead
make that store a deep copy.

## Recommendation

Defer to the user. Lean **(b)** unless a Track B port concretely needs FPC
sharing — value semantics is fewer footguns and PXX already behaves that way; the
cost of (a) (full dyn-array ARC through aggregates) is high for a benefit no demo
has needed yet. Revisit if a ported library breaks on it.

## Log
- 2026-06-22 — Filed from the dynarray-aggregate probe. Not a crash; a deliberate
  semantics fork. No code change until the (a)/(b) decision is made.
