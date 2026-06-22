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

## Scope is NARROW — only assignment, not parameter passing (verified 2026-06-22)

PXX already does the context-sensitive thing, and it is the *right* thing:

| context | PXX | FPC | match |
|---------|-----|-----|-------|
| by-value param, mutate an element (`p(a); a[0]:=9`) | caller sees it (shared handle) | same | **yes** |
| `SetLength` inside a by-value-param callee | caller length unchanged (COW) | same | **yes** |
| **`y := x` assignment / record-field copy** | **deep copy (value)** | **shared (reference)** | **no — only here** |

So **parameter passing and recursion already share the handle (reference) with
COW** — no wasteful per-call copy, exactly as expected. The ONLY divergence is
the **assignment / whole-record-copy** site, where PXX makes an independent copy.

## Why it matters (and why PXX's choice is defensible)

FPC dynamic arrays are reference types *everywhere*, including plain assignment —
so FPC needs an explicit `Copy()` when you DON'T want an alias, and copying a
record silently aliases its array field (mutating one record's field mutates the
"copy"). That is the dark-afternoon debugging trap. PXX instead gives **value
semantics at the assignment site** (a record copy is a real copy; no aliasing
surprise) while keeping **reference semantics at the call boundary** (cheap,
recursion-friendly, no surprise there either). That split is arguably the more
intuitive design — the user agrees FPC's assignment-aliasing is a nuisance.

The only cost: a ported FPC/Delphi library that *relies* on assignment-time
array sharing would behave differently — invisibly, until a
mutation-through-an-alias is observed.

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

## Recommendation / direction (user-aligned)

Keep PXX's value-on-assignment as the **default** — it is the nuisance-free
behaviour and the divergence is confined to one site. The likely end state is
**"do both"**: a compiler switch that selects FPC reference-on-assignment for
ports that need it, value-on-assignment (default) otherwise. Candidate surface: a
`{$...}` directive or a `--`/`-d` flag, scoped to assignment-time dyn-array (and
managed-aggregate) copy. Implementation only at the assignment/record-copy site —
parameter passing already matches FPC and must stay reference (do NOT touch the
call boundary).

**Status: low priority, documented, no code yet.** The user may research (or we
both) before choosing the switch surface + default. Open items to settle first:

1. ~~Confirm deep-copy of a managed *element* type at the assignment site.~~
   **Verified 2026-06-22 — works, no segfault.** `y := x` for a record with an
   `array of AnsiString` field deep-copies the strings (PXX `x0=aa` stays
   independent while `y0=ZZ`; FPC shares → `x0=ZZ`). Array-of-records-with-string
   and a dyn-array-field-of-records-with-string both round-trip correctly on PXX.
   So value-on-assignment already handles managed elements safely.
2. Decide the switch surface + name and whether the default ever flips per
   `{$mode}` (delphi/fpc) for mimic-fpc.
3. If (a)-style FPC sharing is ever the default, it pulls in full dyn-array ARC
   through aggregates (retain/release on copy + scope exit) — the
   feature-cross-managed-aggregates template.

## Log
- 2026-06-22 — Filed from the dynarray-aggregate probe. Not a crash; a deliberate
  semantics fork.
- 2026-06-22 — Verified the divergence is **assignment-only**: PXX param-passing
  already matches FPC (shared handle + COW). User aligned on value-on-assignment
  default; likely resolution is a compiler switch to "do both". Low prio,
  documented, no code until the switch surface/default is chosen.
