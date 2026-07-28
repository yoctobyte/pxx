---
track: A
prio: 70
type: bug
---

# Storing a class into a Variant did not build on i386 or aarch64

`v := someObject` compiled on x86-64 and failed the other two variant-capable
backends with

```
error: Variant :=: this scalar type not yet supported
```

Reported by Track T as `test-i386#src:examples/net/httpdemo.pas` and
`test-arm32#src:examples/net/httpdemo.pas` (STILL-RED through 5174d000e76f).

## Cause

Three backends implement variants — x86-64, i386, aarch64 (arm32 reaches them
through the same lowering). Each carries its OWN scalar-kind → VType table, and
only x86-64's had the `tyClass -> VT_OBJECT` arm plus the matching
`PXXObjRetain` on the payload. The i386 and aarch64 tables fell through to
`Error`, so the build stopped rather than miscompiling — loud, but only on
those targets, which is why it showed up as a cross-target red on a file that
builds fine natively.

Both backends were missing it in TWO places each: the variant STORE arm and
`IR_VAR_BOX`.

## Fix

- `ir_codegen386.inc`: `tyClass -> VT_OBJECT` in `VariantTagForTk386` (the
  shared helper both sites call), plus a class arm at the store and at
  `IR_VAR_BOX` that calls `PXXObjRetain` before pushing the payload, so the
  slot owns its reference exactly as on x86-64.
- `ir_codegen_aarch64.inc`: the same two tables gain `tyClass`, and a new
  `EmitObjRetainA64` (x0-preserving, mirroring `EmitStrIncRefA64`) is called
  from both arms.

Verified: a store/clear loop over a class-valued variant runs correctly under
qemu on i386 and aarch64, and `examples/net/httpdemo.pas` builds on i386,
aarch64 and arm32.

Behind it was a SECOND wall on every target, fixed with it — see
[[bug-b-sysutils-and-pylib-exception-declarations-diverged]].
