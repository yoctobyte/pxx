---
slug: feature-a-i386-refuses-a-by-value-record-parameter-on-the-internal-convention-so-lib-rtl-image-does-not-build
track: A
prio: 50
type: feature
status: done
found: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "i386 accepts a by-value RECORD parameter only for cdecl; on the internal convention it still refuses, because the internal CALLER pushes the address for records of 8 bytes or less and the callee half would read bytes — a silent caller/callee disagreement. The refusal is therefore CORRECT and load-bearing, and the work is the caller half. Cost: lib/rtl/image.pas declares ImageSetPixel(...; c: TRGBA), so the unit does not build for i386 and neither do examples/fm or examples/raytracer, both of which build for arm32, aarch64, riscv32 and xtensa."
---

# i386 refuses a by-value record parameter on the internal convention, so `lib/rtl/image.pas` does not build

Found by compiling `examples/` across five backends against the x86-64 oracle
(`umbrella-cross-target-codegen-is-correct`, 2026-09-02):

```
fm        | i386:BUILD arm32:ok riscv32:ok aarch64:ok xtensa:ok
raytracer | i386:BUILD arm32:ok riscv32:ok aarch64:ok xtensa:ok
```

Both are the same failure, and it is in the RTL rather than in the examples:

```
target i386: only ordinal/pointer parameters supported yet
  in: ./compiler/../lib/rtl/image.pas
  near: ; c : TRGBA ) ;
```

`lib/rtl/image.pas:24` — `procedure ImageSetPixel(var img: TImage; x, y: Integer;
c: TRGBA);`. `TRGBA` is a 4-byte record passed by value. **i386 is the only
target that refuses it**, so the whole unit is unbuildable there and every
program that draws is unbuildable with it.

## THE REFUSAL IS CORRECT — do not lift it

`ir_codegen.inc:1616` already supports by-value records **for cdecl**, and the
comment beside it says exactly why the internal convention still refuses, in its
own words:

> *"GATED ON ProcCdecl, and the gate is the whole point. Pascal passes a record
> of 8 bytes or less BY VALUE (IsRef stays False), so an ungated test would
> accept those here too — while the INTERNAL i386 caller still pushes their
> ADDRESS. That is a caller/callee disagreement about what the slot contains,
> which is the exact failure this ticket exists to prevent, and it would be
> silent. The internal convention keeps its old refusal until its caller half is
> written."*

So this is **not** "i386 is missing a feature that four other backends have and
someone should delete the check". Deleting the check produces a callee reading
bytes where the caller pushed a pointer — silently, on every small record. The
work is the **caller half of the internal convention**, and the refusal is what
is keeping i386 correct until it exists.

(Checked deliberately before filing, on frankA's rule that a refusal is a
hypothesis about the language and can be the only thing keeping a program right.
Here it is.)

## What to build

The i386 internal-convention CALLER must push a small record's BYTES where the
callee now expects them, matching the cdecl arm that already works — then the
`ProcCdecl` gate can widen. Note the direction difference the same comment
describes: the internal convention pushes left-to-right and cdecl puts arg0
lowest, so the two arms walk opposite ways over the same widths.

## Gate

`lib/rtl/image.pas` must build for i386, and `examples/fm/fm.pas` and
`examples/raytracer/raytracer.pas` must build AND match the x86-64 output there,
as they already do on arm32, aarch64, riscv32 and xtensa. A test that only
exercises a cdecl record parameter does not cover this — that arm already works.

## Bound

HEAD `eabd599ee`, compiler `58620a6d3662`. i386 is the only target of the six
that refuses; verified by building the same two programs for all five cross
targets.

## Resolved 2026-09-02 (frankC) — the caller half exists, so the refusal was lifted

The order the ticket asked for, in one commit because either half alone is a
silent disagreement:

1. **Caller** (`ir_codegen386.inc`, the direct ladder's new `A32_RECORD` arm,
   joining the indirect and virtual ones): a 5..8 byte record's VALUE is already
   in `edx:eax` — i386's `IR_LOAD_SYM` widens a record of at most one machine
   pair exactly as arm32 and riscv32 do, the address form being the >8-byte arm
   above it. `push edx` then `push eax`, so the low dword is at the lower
   address and the callee's copy loop, which walks dwords upward from
   `[ebp+8+sz]`, reads the record in its own order.
2. **Callee** (`ir_codegen.inc`): the four `ProcCdecl` gates come off — the
   unknown-size refusal, the "only ordinal/pointer parameters" predicate, the
   parameter-width walk and the frame-slot copy. The unsized-record refusal
   stays on both conventions: counted as 4 bytes it would shift every parameter
   after it.

A ≤4-byte record — `TRGBA`, the one in the report — never needed a new class:
`Arg32Class` answers `A32_WORD`, one word IS the record, and the callee copy
loop moves exactly one dword.

Verified: `test_byvalue_record_param_every_call_shape` (direct/virtual/indirect ×
4/8/12/16 bytes, plus a copy-semantics check and a `const` by-ref control) passes
on **all six** targets; `test_arm32_record_byval_wide`, which i386 could not
build at all, passes there now; `examples/fm` and `examples/raytracer` build for
i386 and their output is byte-identical to the x86-64 oracle, as is that of 15
other examples including `player`, which also draws through `image.pas`.

That sweep is the positive control as well as the check: `raytracer` moved from
BUILD-refused to matching, so the instrument does discriminate the state this
ticket is about rather than passing everything put in front of it.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 18b3ec2a6.
