# JSON library — parser + serializer (with a roundtrip test app)

- **Type:** feature
- **Status:** blocked (impl done; lib-test gate blocked on re-pin)
- **Blocked-by:** bug-impl-prescan-codegen-regression
  (re-pin past v32 is unsafe until that silent codegen regression is fixed)
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** one of the demo-eligible-as-library items from
  idea-demo-app-candidates (was survivor #2). Reusable RTL unit whose acceptance
  test *is* the demo. Sibling to feature-hashing-library /
  feature-compression-library / feature-bignum-library / feature-sat-solver-library.
  Per [[project_own_rtl_from_scratch]]: write our OWN unit with FPC-ish naming,
  do NOT port FPC `fpjson`.

## Goal

A `JSON` unit: parse a UTF-8 JSON string into a value tree, navigate/mutate it,
serialize back (compact + pretty). FPC-flavored surface so existing code style
carries, but our own elegant implementation.

## Surface (sketch — finalize when picked up)

- value tree: object / array / string / number / bool / null (a tagged union or
  small class hierarchy — exercises **variant or class/VMT** lane)
- `Parse(s): TJSONValue` (raises on malformed — exceptions lane)
- typed access: `AsString` / `AsInteger` / `AsBoolean`, `Items[i]`, `Values[key]`
- `ToString(pretty: Boolean)` serializer

## Coverage

managed strings (heavy) · dynamic arrays (array nodes) · collections/hashing
(object members) · recursion (nested parse/emit) · variant or class hierarchy ·
exceptions (parse errors). Hand-written JSON is normal practice, so this does
**not** undermine the "use a library" story.

## Acceptance / oracle

- **Roundtrip identity:** `Parse(s) -> ToString -> Parse` yields an equal tree;
  canonical re-emit is byte-stable.
- A fixed sample-document set parses + re-emits byte-identical across all targets.
- Demo: `examples/json/` round-trips a bundled set, prints canonical form.

## Constraints

Own `.pas` unit (not `.inc`); FPC-ish naming; no `fpjson` port; must not regress
self-host / cross-bootstrap.

## Log
- 2026-06-19 — Opened from the demo/library organization pass.
- 2026-06-22 — **Implemented** (track B), commit 3050ec5: `lib/rtl/json.pas`
  (TJSONValue tree + TJSONReader recursive-descent parser + canonical compact/
  pretty serializer; numbers kept as raw lexeme for byte-stable re-emit; EJSONError
  on malformed input; \uXXXX -> UTF-8). Oracle `examples/json/jsondemo.pas` covers
  roundtrip identity, canonical stability, escapes/unicode, typed access, and
  parse-error exceptions; ends `ALL OK`. Wired into `make lib-test` + `make demos`.
  Verified green against a freshly self-hosted compiler (HEAD).
  **Blocked:** the pinned stable is v32, which predates `obj.Free` (562eb95) and
  bare `Copy` (dd706ff) that the lib needs. Re-pinning past v32 is currently unsafe
  because of bug-impl-prescan-codegen-regression (silent miscompile in unit impl
  sections, introduced by 7ba91bf). Once that bug is fixed and the stable re-pinned,
  `make lib-test` goes green and this closes. Code is committed but NOT pushed
  (gate red until then).
