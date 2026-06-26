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

## Resolution (2026-06-25, v65)

The aarch64 and arm32 backends rejected `IR_LOAD_MEM` of a `tyRecord` value
("load through pointer of this type not yet supported") — the path a small
(<=8-byte) by-value record argument takes (`ir.inc` wraps a record call/binop
result in `IR_LOAD_MEM tyRecord`, loading its packed bytes into a register, like
x86-64).

Fix: allow `tyRecord` in both backends' `IR_LOAD_MEM` type allow-list.
- **aarch64**: `TypeSize(tyRecord)=8` -> the existing `sz=8` path emits
  `ldr x0,[x0]`, loading the whole packed record (<=8 bytes), mirroring x86-64.
  Fully correct for <=8-byte records (`Sum(Mk(3))`=12, an 8-byte record=15/30).
- **arm32**: `ldr r0,[r0]` loads the packed bytes for a <=4-byte record (the
  `TRGBA` repro). Verified `Sum(Mk(3))`=12.

Regression `test/test_record_temp_byval_arg.pas` (temp + named, prints `18`,`46`)
in `make test`, `test-aarch64`, `test-arm32`. Self-host byte-identical (x86-64
codegen untouched); pinned v65.

### Residual (separate, pre-existing — not this temp bug)

- **arm32 records > 4 bytes**: the arm32 by-value record-param marshalling/prologue
  only carries the low 4 bytes (a *named* 8-byte record arg already dropped its
  high word before this fix), so a >4-byte record arg is wrong on arm32. Needs the
  arm32 record-param ABI widened to r0:r1 (caller + prologue), tracked here as the
  remaining arm32 item.
- **i386**: still rejects *any* by-value record param ("only ordinal/pointer
  parameters supported yet") — a broader i386 maturity gap, untouched.
