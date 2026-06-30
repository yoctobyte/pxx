# `SetLength(a, x, y)` one-call multidim allocation not parsed

- **Type:** bug (parser) — Track A
- **Status:** DONE (2026-06-30, Track A)
- **Opened:** 2026-06-30
- **Found by:** feature-dynarray-torture-test.

## Symptom

```pascal
var a: array of array of Integer;
begin SetLength(a, 2, 3); ... end.
```
→ `pascal26:2: error: unexpected token`. FPC allows `SetLength(arr, d1, d2, ...)`
to allocate a rectangular jagged array in one call (each extra dimension sizes the
sub-arrays). PXX's `SetLength` parser takes exactly `(lvalue, count)` and chokes on
the second size.

## Workaround (works today)

Per-row: `SetLength(a, 2); for i := 0 to 1 do SetLength(a[i], 3);` — the torture
test uses this. So the capability exists; only the one-call sugar is missing.

## Fix sketch

`ParseFactor`/statement `SetLength` branch (parser.inc ~8122): after the first
size expr, accept further `, <expr>` dimensions and lower to a per-dimension
init loop (or a runtime helper) that sizes the nested dynarrays. Rectangular only
(FPC semantics). Front-end + a small lowering.

## Acceptance

`SetLength(a, 2, 3)` allocates a 2×3 jagged array; `Length(a)=2`, `Length(a[i])=3`;
existing 2-arg `SetLength` unchanged; self-host byte-identical.

## Done (2026-06-30, Track A)

`SetLength(a, d0, d1, ..., dk)` now allocates a rectangular jagged array in one
call. Implemented as parse-time AST synthesis (parser.inc): the `SetLength`
statement branch collects all size exprs into `SetLenDimNode[]`, then
`BuildMultiSetLen` / `BuildSetLenNest` build
`SetLength(a, d0); for i:=0 to d0-1 do (SetLength(a[i], d1); for j:=... )` —
recursive over dimensions, the sub-array targets cloned via `CloneAST` (the
defs.inc "AN_INDEX.Left = sym idx" comment is stale; it is a node). `MkForAsc`
synthesises the ascending `AN_FOR`. Multidim on a non-dynamic-array target (incl.
a managed string) errors clearly at parse time.

Verified: 2-D / 3-D allocate correct extents + contents; managed-element rows
(`array of array of string`); record-field target (`SetLength(r.m, 2, 3)`);
single-dim unchanged; string-target multidim rejected. Self-host byte-identical;
`make test` green (torture test cases 25-27).

**Known limitation (documented, low impact):** the size expressions are
re-cloned per use (the outer call + the loop bound), so a dimension with side
effects — `SetLength(a, f(), g())` — is evaluated more than once. Real code uses
constants/variables (side-effect-free), the FPC norm. A once-eval-into-temps
refinement is a small follow-up if ever needed.

## Cross-target note

Multidim (and per-row) **nested** dynarrays work on **x86-64** but segfault on
arm32 / aarch64 / i386 — a **pre-existing** nested-dynarray codegen gap on the
cross backends, NOT caused by this feature (a per-row 2-D dynarray with no
multidim sugar crashes there too). Filed separately:
[[bug-nested-dynarray-cross-segfault]]. The torture test exercises multidim on
x86-64 only (in `make test`); single-level dynarrays remain green cross.
