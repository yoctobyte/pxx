# Plain (non-`const`) by-value record param >8B rejects a temporary argument

- **Type:** bug (compiler — call-arg lowering)
- **Track:** A — `compiler/**`
- **Status:** backlog (filed by Track B)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-raytracer]] — vector algebra over a 24-byte
  `Vec3 = record x, y, z: Double end`, composing `VAdd(VScale(V(…), s), …)`.
- **Relation:** the sibling [[bug-const-byref-record-param-temp]] (done,
  2026-06-19) fixed exactly this for **`const`** record params. This is the
  remaining, symmetric gap for **plain by-value** record params.

## Symptom

A function-result temporary passed to a **plain by-value** record param fails
when the record is larger than 8 bytes:

```pascal
type Vec3 = record x, y, z: Double end;          { 24 bytes }
function V(x,y,z: Double): Vec3;
function VScale(a: Vec3; s: Double): Vec3;        { plain by-value }
function VAdd(a, b: Vec3): Vec3;

z := VAdd(VScale(V(1,1,1), 0.5), V(2,2,2));
        { pascal26: error: by-reference argument must be a variable () }
```

The exact same code compiles and runs correctly if the params are declared
`const`:

```pascal
function VScale(const a: Vec3; s: Double): Vec3;  { OK }
function VAdd(const a, b: Vec3): Vec3;            { OK -> z.x = 2.500 }
```

Named-variable arguments also work for the plain by-value form; only a
**temporary** (function result) is rejected.

### Size dependence

| record | temp as plain by-value arg |
| --- | --- |
| 8 bytes (1×Double / fits a register) | OK |
| 12 bytes (3×LongInt) | error |
| 16 bytes (2×Double) | error |
| 24 bytes (3×Double) | error |

So it is the same root cause as the truncation work in
[[bug-record-byvalue-arg-truncation]] (done): records >8 bytes are passed
by-reference internally (with a callee copy for by-value semantics), and the
AST-path call-arg check only binds a true lvalue — so a temporary is refused.

## Why the `const` fix didn't cover this

`bug-const-byref-record-param-temp`'s fix relaxed the call-arg check **only for
params flagged `const`** (`ProcParamIsConst[...]`, parser.inc ~3328 / ~5862),
deliberately keeping `var`/`out` strict. A plain by-value param is neither
`const` nor `var`, so it falls through to the strict path even though, for a
>8-byte record, it is lowered by-ref exactly like a `const` param (the
`needTemp` materialization in `IRLowerCallArg` already handles it).

## Fix

Extend the temporary-materialization allowance to **plain by-value record
params** (records passed by-ref for ABI reasons), not just `const` ones. The
callee already copies for by-value semantics, so a hidden-local temp is sound.
`var`/`out` must still require a real lvalue.

## Done when

- `VAdd(VScale(V(1,1,1), 0.5), V(2,2,2))` with plain by-value params compiles and
  gives `z.x = 2.5`.
- Nested/mixed temp+named args correct; `var` param still errors on a temp.
- `examples/raytracer` no longer needs `const` solely to satisfy the compiler.
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Workaround (in use)

`examples/raytracer` declares its vector-input params `const` — which is also the
idiomatic, more efficient style for non-mutated record inputs, so the demo stays
platonic. This ticket tracks making the bare by-value form work too.
