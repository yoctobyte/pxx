# aarch64/arm32: record temporary as a by-value arg fails codegen

- **Type:** bug (compiler — aarch64 + arm32 backends)
- **Track:** A — `compiler/**`
- **Status:** backlog (filed by Track B)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-raytracer]] adding PNG output —
  `ImageSetPixel(img, x, y, MakeRGBA(r, g, b, 255))` passes a `TRGBA` (4-byte
  record) function-result temporary by value; compiles + runs on x86-64, fails
  codegen on aarch64 and arm32.
- **Relation:** the x86-64 analog is the parse-level
  [[bug-plain-byvalue-record-param-temp]]. Here the AST check passes and it dies
  in the aarch64/arm32 *backend* instead, on a different (smaller) record.

## Symptom

Passing a function-result temporary as a by-value record argument:

```pascal
type R = record a, b, c, d: Byte end;        { 4 bytes }
function Mk(v: Byte): R;
function Sum(x: R): Integer;

n := Sum(Mk(3));     { aarch64/arm32: target ...: load through pointer of
                       this type not yet supported }
```

| target | result |
| --- | --- |
| x86-64 | OK |
| aarch64 | error: load through pointer of this type not yet supported |
| arm32 | error: load through pointer of this type not yet supported |
| i386 | error: only ordinal/pointer parameters supported yet (broader — see note) |

A **named variable** argument works on every target:

```pascal
r := Mk(3); n := Sum(r);     { OK on aarch64/arm32 }
```

So the aarch64/arm32 backends materialize a by-value record param from a real
lvalue fine, but cannot lower a temporary (the hidden-local copy + load path the
x86-64 backend uses).

## Impact

Idiomatic value-style record APIs — `ImageSetPixel(img,x,y,MakeRGBA(...))`,
vector/colour algebra, small value structs — won't cross-compile to aarch64/arm32
when an argument is a call result rather than a named local. Worked around in
`examples/raytracer` by materializing a named `TRGBA c := MakeRGBA(...)` before
`ImageSetPixel` (idiomatic anyway), which restores the aarch64 build.

## Note — i386 is broader

i386 reports `only ordinal/pointer parameters supported yet` for the same code:
that backend does not take **any** by-value record param (named or temp), a wider
gap than the temp-specific aarch64/arm32 one. Track i386 record-by-value params
separately if not already covered by the i386 maturity work.

## Done when

- `Sum(Mk(3))` compiles + runs correctly on aarch64 and arm32 (matches x86-64).
- `examples/raytracer` no longer needs the named-`TRGBA` materialization for
  aarch64.
- Regression test in the aarch64/arm32 cross suites; self-host unaffected.
