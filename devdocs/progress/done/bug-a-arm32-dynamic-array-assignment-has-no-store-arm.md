---
summary: "arm32/riscv32: `b := a` on a DYNAMIC array segfaults — IR_STORE_SYM has no dyn-array arm in those backends, and they carry no dyn-array ARC machinery at all (no retain, no release, no scope-exit cleanup)"
type: bug
track: A
prio: 75
owner: claude-A
---

# arm32 / riscv32: whole dynamic-array assignment has no backend store arm

- **Type:** bug — Track A (arm32 / riscv32 backend, dynamic-array ARC)
- **Status:** done
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

## Resolution (2026-08-05)

The diagnosis in the ticket held. `IR_STORE_SYM` simply had no dynamic-array arm
in `ir_codegen_arm32.inc` or `ir_codegen_riscv32.inc`, so a dyn-array `b := a`
fell through to the scalar store and published the wrong one of `IR_LEA`'s two
read/write results.

**It was smaller than the ticket feared.** The ticket sized this as "a
structural port of the retain / element-aware release / scope-exit protocol"
because `grep DynArrayRetain` matched only `ir_codegen.inc`. That grep was
misleading: x86-64's *retain* is open-coded inline (`inc qword [rax-16]`), but
its *release* is already an ordinary call to `PXXDynArrayRelease(data, desc)`,
and `PXXDynArrayIncRef` exists in the RTL as a plain proc too. Both backends
already had everything needed to call them — `EmitSlotAddrRISCV32` /
`EmitLoadImmArm32`, `EmitLoadDataRef*`, `GetOrAllocSymRTTI`, `EmitCallProc` —
because `SetLength` already goes through `PXXDynSetLen` the same way.

The dynarray header is a fixed **16 bytes on every target**
(`PXXAlloc(16 + n * elSize, 8)`, refcount at -16 and length at -8, both
pointer-width via `PWord`), so the RTL helpers need no 32-bit variant. Calling
them beats open-coding the refcount arithmetic twice.

So each backend got one arm mirroring x86-64: retain the new handle, publish it,
release the old one through the symbol's layout descriptor (element-aware, so a
managed-element array releases its elements). Move semantics preserved — a fresh
user-function result already carries the +1, so the retain is skipped for
`IR_CALL` with `IRA >= 0`, the same discrimination x86-64 makes.

**The arm must precede the `tyAnsiString` arm** in both backends: for an
`array of string` the symbol's `TypeKind` names the ELEMENT, so the string arm
would otherwise claim the array. Ordering it first is load-bearing, not
cosmetic.

**Verified.** All four reductions from the ticket pass on arm32 and riscv32
(local:=local, global:=local, via-function read, the 7-line `g8`). Both real
consumers now produce output identical to x86-64:

    lib_zlib arm32: MATCHES x86-64   (was SIGSEGV)
    lib_png  arm32: MATCHES x86-64   (was SIGSEGV)

Locked in as `test/test_dynarray_whole_assign.pas` — plain and managed element
types, local / global / through-a-function, destination already holding a
handle, and self-assignment. Verified identical on x86-64, i386, arm32, aarch64
and riscv32.

### Found while cross-checking: x86-64 is the odd one out

Comparing all five targets against FPC turned up a **separate pre-existing
divergence in the opposite direction**: `b := a` on a dynamic array
copy-on-writes on **x86-64**, so writes through either name are invisible to the
other. FPC and all five other targets alias, as reference-type semantics
require. `pinned` behaves identically, so it is not recent. Filed as
`bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing` (prio 65) with the
measured three-way table and the direction question called out.

Consequently the regression test here **deliberately does not assert aliasing** —
it asserts only what this fix is about (a usable array: correct Length, readable
elements, no crash), so it stays green whichever way that ticket is settled.
Whoever takes it should add the aliasing assertions to this same test.

**Gate:** `testmgr --tier quick` 15/15 green; `tools/selfhost_fixedpoint.sh`
converges in 2 rounds from `pinned` and agrees with `compiler/pascal26`;
`tools/lib_cross_sweep.sh` before/after diffed (backend change, cross-target
blast radius).

### Cross-sweep, before and after

`tools/lib_cross_sweep.sh` against the same tree with and without the arm:
**32 failing rows -> 27. No regressions.**

Cleared: `lib_zlib` arm32, `lib_png` arm32, `lib_http` arm32, `lib_http_gzip`
arm32, `lib_http_pool_concurrent` arm32, `lib_sockets` aarch64. The http/sockets
rows are a bonus — they use dynamic-array buffers and were failing for the same
reason, which is more of the arm32 surface than this ticket claimed.

One row in the "new" column, `lib_http_pool_concurrent` i386, is **flaky, not a
regression**: across the three sweeps it lands on i386, on arm32, on both, or on
neither, and four direct repeated runs against the x86-64 reference all match.
It is a concurrency test.

## Log
- 2026-08-05 — resolved, commit 9b78948b6.
