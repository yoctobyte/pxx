
---

## 2026-08-29 — the `-O1` leaf-operand arm ported to aarch64. LANDED (`1185b3489`).

Fourth and last of the four. **The largest single result in this campaign, and
it came from measuring a gap nobody had priced rather than from a clever
transform.**

### The gap

Every integer binop on aarch64 emitted the same four-instruction dance,
*regardless of operand shape*:

```
    eval left -> x0
    str x0, [sp, #-16]!     <- push
    eval right -> x0
    mov x1, x0
    ldr x0, [sp], #16       <- pop
```

x86-64 has collapsed this since **`-O1`** when the right operand is a constant
or a leaf sym. aarch64 had **no such arm at all** — not even for a constant —
so it paid two stack memory ops and a register shuffle on *every* binop in
*every* program.

### Priced before it was written

`PXXDBG=a.a64binop` (report-only, added in the same commit) classifies the right
operand of every integer binop reaching that path:

| program | integer binops | CONST | LEAFSYM | collapsible |
| --- | --- | --- | --- | --- |
| `compiler.pas` | 54056 | 80.9% | 12.6% | **93.4%** |
| mandelbrot | 4953 | 77.7% | 16.3% | **93.9%** |
| chess | 4917 | 77.7% | 16.0% | **93.6%** |
| jsondemo | 8016 | 77.9% | 16.0% | **93.9%** |

Four populations, all within half a point of each other. That consistency is
itself informative: it is a property of *how Pascal is written*, not of any one
program.

### What landed, and the contract that made it safe

The CONST half. A constant has no side effects and cannot observe the left
operand, so it is materialised **after** the left is in x0, straight into x1
where the op arms already expect it.

> **The downstream register contract is IDENTICAL — x0 = left, x1 = right.** So
> every op arm, `{$Q+}` checked forms included, works unchanged. This is a port
> rather than a rewrite precisely because it changes *how x1 is populated* and
> nothing else.

`EmitLoadImmA64` writes only its destination register, and `IR_CONST_INT` is
exactly `EmitLoadImmA64(0, IRIVal[node])` with no truncation step to lose — both
checked rather than assumed.

**mandelbrot, aarch64 `-O3`: 725196 -> 683112 bytes. 42084 bytes and 10521
instructions removed, 5.8%.**

### What was deliberately NOT done

The LEAFSYM half — another 12.6-16.3% of every integer binop. It needs the right
operand in x1 while the left sits in x0, and `EmitLoadVarA64` hardcodes x0
behind residency, float-residency, dyn-array-handle and sign-extension arms.

A load-to-x1 twin would duplicate all of that, and **the dyn-array comment
inside that very function records its arms having already drifted apart once,
with a segfault as the result.** The cheap alternative — `mov x1, x0`, load
right into x0, read the operands reversed — is valid only for commutative ops,
so it is the same second path in a different costume.

Filed as `feature-opt-a64-loadvar-destination-register` (A, p55) with the
population, the reason the cheap alternative fails, and the specific risk: the
extension arms encode their destination *in the opcode constants*, so a register
parameter has to reach into each encoding rather than be OR-ed in uniformly.

### Gating choice, stated because it diverges from the sibling

Behind **`-O3`**, though the x86-64 arm is `-O1`. Mirroring at `-O1` would have
bought wider differential coverage; `-O2` being the proven default and this
being a hot path on a target verifiable only through an emulator decided it the
other way.

### Verification

- self-host fixedpoint `9a671a37afbe`
- aarch64 differential vs the pre-port compiler, **10 programs x `-O0`/`-O2`/`-O3`
  under qemu — 30 pairs compared, 0 differ**: div/mod mixed signedness, integer
  cast truncation, int64-of-nativeint, sized names, `{$Q+}` narrowing overflow,
  div-by-zero raises, and the three `-O3` residency stress programs. The harness
  reports its comparison count and exits 2 if it compared nothing.
- default `-O` corpus identical on all six targets, 25 rows, **isolated against a
  build of HEAD with only this change reverted** — necessary because the raw
  comparison against this morning's binary showed an `exc` x86-64 row moving that
  turned out to belong to another lane.

### Not timed, and here the reason is sharper than before

qemu does not model store-to-load forwarding, and removing two stack ops per
binop is *mostly* about exactly that. A qemu figure would understate this by an
unknown factor, which is worse than no figure. Code size and instruction count
are exact and are what this stands on.

`chess` does not build for aarch64 at all (stackful generator, x86-64 only) —
pre-existing and unrelated, but it means the aarch64 corpus is thinner than the
x86-64 one.
