---
summary: "arm32/riscv32: `b := a` on a DYNAMIC array segfaults — IR_STORE_SYM has no dyn-array arm in those backends, and they carry no dyn-array ARC machinery at all (no retain, no release, no scope-exit cleanup)"
type: bug
track: A
prio: 75
---

# arm32 / riscv32: whole dynamic-array assignment has no backend store arm

- **Type:** bug — Track A (arm32 / riscv32 backend, dynamic-array ARC)
- **Status:** urgent
- **Opened:** 2026-08-05
- **Found by:** Track A, splitting
  `bug-a-arm32-write-after-free-kills-four-lib-tests`. That ticket assumed one
  cause below all four failing lib tests. There were **two**: the by-value
  managed-record ABI defect (fixed, took ecdsa/rsa/rsa_pss) and this one, which
  is what `lib_png` was actually dying on.

## Repro — 7 lines, no units

```pascal
program g8;
var a, b: array of Byte;
begin
  SetLength(a, 8); a[3] := 42;
  b := a;
  writeln('len=', Length(b), ' [3]=', b[3]);
  writeln('survived');
end.
```

    x86-64  : len=8 [3]=42, survived
    aarch64 : len=8 [3]=42, survived
    arm32   : SIGSEGV in Length(b)
    riscv32 : SIGSEGV in Length(b)

Pre-existing: the **pinned** stable compiler produces the identical crash, so
this is not a recent regression.

The assignment itself "completes" and the SOURCE stays intact — `Length(a)`
still reads 8 afterwards. Only the destination is broken, which is what makes
it read as memory corruption somewhere later rather than as a bad assignment.

## Diagnosis

`compiler/ir_codegen.inc`'s `IR_STORE_SYM` opens with a dynamic-array arm
(line ~2707):

```
if Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
  { retain the new data pointer, publish it, release the old one }
```

**`ir_codegen_arm32.inc` and `ir_codegen_riscv32.inc` have no such arm**, so a
dyn-array `b := a` falls through to the scalar store. `IR_LEA` on a dynamic
array is read/write-gated in those backends (handle in read position, SLOT
ADDRESS in write position), so the scalar path publishes the wrong one of the
two and `Length(b)` dereferences it.

This is not a missing `if`. Those backends carry **no dynamic-array ARC
machinery at all** — `grep -n "DynArrayRetain\|DynArrayReleaseForSym"` matches
only `ir_codegen.inc`, and neither backend has a managed-local scope-exit
cleanup for dynamic arrays. So the fix is a structural port of the retain /
element-aware release / scope-exit protocol, not a small patch. Sizing it
honestly is the first task, not writing the arm.

## How it reached `lib_png`

Bisected down from the segfault, each step measured:

    lib_png -> PngDecodeRGBA -> InflateZlib -> InflateRaw -> ReadBits
            -> gData[bytePos], where `gData: TByteArray` is a module global
               assigned `gData := src`

`zlib.pas` keeps the input in module globals precisely to dodge older
dynamic-array defects (see the comment above its `gData` declaration) — so the
one construct it relies on is the one that is broken here.

`lib_zlib` itself is the other casualty and the more direct one: it segfaults on
arm32 (rc 139) in `tools/lib_cross_sweep.sh` both before and after the by-value
record fix, so it is a clean witness for THIS bug with no crypto in the way.
Use it as the acceptance test alongside `lib_png`.

## Severity

`b := a` on a dynamic array is not exotic; it is how any buffer is handed
around. On two supported 32-bit targets it segfaults. Anything using `zlib`,
and by extension `png`, is dead on arm32/riscv32 today.

## Related

- `bug-a-arm32-write-after-free-kills-four-lib-tests` — the sibling cause, fixed
  separately; that fix is what makes this one the *only* remaining reason
  `lib_png` fails on arm32.
- Both were reachable only because `tools/lib_cross_sweep.sh` runs the lib tests
  on cross targets; `lib-test` is x86-64 only.
