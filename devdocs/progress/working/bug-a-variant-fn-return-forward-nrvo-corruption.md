---
track: A
prio: 55
type: bug
---

# Variant FUNCTION forwarding another Variant call's result corrupts the value

Found building `pyeval` (feature-lib-pyexec M1), 2026-07-21. Verified with
`compiler/pascal26` (not a stale-binary artifact).

## Symptom

A **Variant-returning function** whose `Result` (or a local Variant) is assigned
from another Variant-returning **call** produces a corrupt value — commonly the
VType word survives but the Payload reads 0, or the whole 16 bytes read as a
stack address. Looks like an 8-byte-instead-of-16 copy / NRVO hidden-dest
aliasing between the function's Result slot and locals.

## Minimal repro

```pascal
type PVRec = ^TVRec; TVRec = record VType, Payload: Int64; end;
function mk: Variant;
begin PVRec(@Result)^.VType := 2; PVRec(@Result)^.Payload := 77; end;
function relay: Variant;
begin relay := mk; end;              { forwards a Variant call into Result }
...
t := relay();                        { reads GARBAGE (vtype=stack addr, payload=0) }
t := mk();                           { OK — mk BUILDS Result via pointer writes }
```

- `t := mk()` in main / any procedure: **OK**.
- `relay := mk` (function tail-forwards a Variant call): **BROKEN**.
- Inside a function, `var x: Variant; x := mk` gives VType=2 but Payload=0.
- The bug is gated on the ENCLOSING routine being a Variant FUNCTION (has an NRVO
  Variant Result). The SAME body inside a **procedure with a `var res: Variant`
  out-param** works: `procedure relay(var res); begin res := mk; end;` → correct.

## Scope / impact

Any Pascal/NilPy code of the shape `function F: Variant; begin F := G(...) end`
(G returns Variant) is suspect — a broad correctness hole, silent. pyeval works
around it by making every node evaluator a `var res: Variant` procedure (see
`compiler/builtin/pyeval.pas` header + memory
`project_variant_fn_return_forward_nrvo_corruption`).

## Likely area

NRVO / hidden-dest assignment for a Variant function Result, where the callee's
16-byte managed-variant return is copied into the caller's Result/local with the
wrong width or an aliased destination. Compare the working procedure-var-param
path (real address) against the function-Result path.
