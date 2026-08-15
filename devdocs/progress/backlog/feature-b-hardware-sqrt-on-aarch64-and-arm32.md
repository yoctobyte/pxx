---
track: B
prio: 20
type: feature
blocked-by: []
summary: "Sqrt is one `sqrtsd` on x86-64 (15x faster than the software path and correctly rounded by IEEE mandate). aarch64 `fsqrt` and arm32 `vsqrt` are the same one-instruction win and both run here under qemu, so the change is verifiable on this box. The portable SqrtSoft stays as the fallback for riscv32/xtensa."
---

# Hardware `Sqrt` on aarch64 and arm32

- **Type:** feature (performance) — **Track B** (`lib/rtl/math.pas`).
- Split out of [[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]] on 2026-08-15,
  which made the software path correctly rounded and then used `sqrtsd` on
  x86-64. That ticket was about correctness; this is only about speed, which is
  why it is not folded into it.

## What landed already, and what this repeats

`Sqrt` on x86-64 is now:

```pascal
{$ifdef CPUX86_64}
function Sqrt(x: Double): Double;
var r: Double;
begin
  asm
    movsd  xmm0, x
    sqrtsd xmm0, xmm0
    movsd  r, xmm0
  end;
  Result := r;
end;
{$else}
function Sqrt(x: Double): Double;
begin
  Result := SqrtSoft(x);
end;
{$endif}
```

Measured on a 3M-call loop: software 575 ms, `sqrtsd` **18 ms**.

aarch64 has `fsqrt d0, d0` and arm32 (VFP) has `vsqrt.f64 d0, d0`. Both are
IEEE-mandated correctly-rounded, so this is a pure speed change with no
accuracy argument to make — the same one already argued and measured for
x86-64.

## Why it is worth doing here specifically

Unlike the dynamic-loader work, **both targets RUN on this box** under
qemu-user for a statically linked binary: `test/lib_math_correctly_rounded.pas`
was executed on i386, aarch64 and arm32 that way while fixing the parent
ticket, and printed `MATHROUND OK` on all three. So the change is verifiable
where it is written, which is not true of most cross-target work here.

## Constraints

- Check the inline-asm encoder actually accepts the mnemonics on those targets
  before writing the Pascal — x86-64's `sqrtsd` is in
  `compiler/asmenc.inc`; the aarch64/arm32 encoders are separate and may not
  carry `fsqrt`/`vsqrt` yet. **If they do not, that is a Track A ticket**, not
  something to add under B.
- riscv32 and xtensa keep `SqrtSoft` — riscv32's F extension is optional and
  the ESP targets are the reason the portable path must stay first-class.
- `SqrtSoft` stays exported and asserted in `lib_math_correctly_rounded` for
  every target, including the ones that get hardware sqrt. That is what keeps
  the fallback from rotting.

## Gate

`lib_math_correctly_rounded` prints `MATHROUND OK` natively and under qemu on
aarch64 and arm32, with the `SqrtSoft` rows still asserted there; a
before/after timing on each; `make lib-test` green.
