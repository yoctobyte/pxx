# JSON library — parser + serializer (with a roundtrip test app)

- **Type:** feature
- **Status:** backlog
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
