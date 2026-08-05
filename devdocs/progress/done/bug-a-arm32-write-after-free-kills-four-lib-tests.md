---
summary: "arm32 only: WRITE AFTER FREE segfaults FOUR lib tests (ecdsa, rsa, rsa_pss, png); reduces to 'call EcdsaP256Verify twice'; -O-independent, x86-64/aarch64 clean"
type: bug
track: A
prio: 75
owner: claude-A
---

# arm32: a write-after-free segfaults four lib tests (reduces to two calls)

- **Type:** bug — Track A (arm32 codegen / managed-value lifetime).
  **Lane is a judgement call**: the source is `lib/rtl/ecdsa_p256.pas` (Track B),
  but identical source is correct on x86-64 and aarch64, and the fault is
  memory lifetime rather than arithmetic — so it is filed to A. Move it if the
  bisect says otherwise.
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** `tools/lib_cross_sweep.sh` — four lib tests segfault on arm32
  and on no other target.

## Scope: this is not an ecdsa bug

| test | arm32 | `-dPXX_HEAP_DEBUG` says |
| --- | --- | --- |
| `lib_ecdsa_p256` | SIGSEGV | `WRITE AFTER FREE in 0x408268e0` |
| `lib_rsa` | SIGSEGV | `WRITE AFTER FREE in 0x408b8178` |
| `lib_rsa_pss` | SIGSEGV | `WRITE AFTER FREE in 0x408eef90` |
| `lib_png` | SIGSEGV | (no message before the fault) |

Three independent tests report the **same diagnostic**, and `lib_png` shares no
code with the other three — it uses `image`/`png`, not `bignum` — so the cause
is below all of them, in the arm32 backend or runtime, not in any one library.
All four pass on x86-64 and aarch64.

## Repro (13 lines, no valid key material needed)

```pascal
program ec4;
uses sysutils, ecdsa_p256;
var qxy, sig: string; k: Integer;
begin
  qxy := StringOfChar(#1, 64); sig := StringOfChar(#2, 64);
  for k := 1 to 3 do
    writeln('call ', k, ' -> ', EcdsaP256Verify(qxy, 'm', sig));
  writeln('survived');
end.
```

    x86-64  : call 1..3 -> FALSE, survived
    aarch64 : call 1..3 -> FALSE, survived
    arm32   : call 1 -> FALSE, call 2 -> SIGSEGV

## What it is NOT — each ruled out by measurement

| hypothesis | test | result |
| --- | --- | --- |
| bad-signature code path | four calls with a **valid** signature | still crashes on call **2** |
| a specific signature value | flip a different byte each iteration | crashes on the 2nd call whatever the value |
| the crypto math | all-`#1` key and all-`#2` signature (garbage) | still crashes on call 2 |
| an optimiser bug | `-O0`, `-O1`, `-O2`, `-O3` | crashes at **every** level |
| copy-on-write string mutation (`bad[64] := ...`, the line it died near) | reduced separately, all 5 targets | **correct everywhere** |

So it is simply: **the second call**, on arm32, regardless of arguments.

## What it IS

Built with `-dPXX_HEAP_DEBUG`:

    pxx-heap: WRITE AFTER FREE in 0x408268e0

and with the poisoning in place it then *survives* — the layout shift moves the
write somewhere harmless. A freed block is written after release, so the first
call leaves a dangling reference that the second call trips over. That points at
managed-value lifetime (refcount release too early, or a temporary freed while
still referenced) in the arm32 backend, not at the library's logic.

## Why urgent

Silent-then-fatal on a supported target, in **crypto verification code** — the
one place a wrong answer or a crash matters most. Any arm32 program that
verifies more than one signature dies on the second.

## Reduction attempts that did NOT reproduce (so the cause is narrower than these)

- **`bignum` on its own** — four rounds of `BigFromInt`/`BigMul`/`BigToStr` on
  arm32: correct, survives. So it is not simply "big-integer code".
- **Generic allocation pressure** — 200 rounds of growing a dynamic array and
  building a string, ~760 KB churned, with and without heap debug: correct,
  survives. So it is not simply "many allocations".

Recording these because they are the cheap hypotheses, and each one ruled out
narrows the search for whoever picks this up.

## Next step for whoever takes it

The playbook's tools already did the hard part; continue with them rather than
by inspection:

- `-dPXX_OBJTRACE` then `grep 0x408268e0` for who retained and released it.
- The address is stable enough across runs to be worth a watchpoint under
  `qemu-arm -g` + `gdb-multiarch`, with `tools/pxx-gdb.py` sourced.
- Compare against `bug-a-aarch64-managed-string-concat-leak` — a managed-value
  lifetime defect on a non-x86 backend is a known shape here, and the two may
  share a cause even though this one is arm32 and that one aarch64.

## Coverage note

Reachable only because `tools/lib_cross_sweep.sh` now runs the lib tests on
cross targets; `lib-test` is x86-64 only and Track T's matrix does not include
them.

## Resolution (2026-08-05)

**The ticket's central premise was wrong, and that is the main finding.** It
reasoned that because `lib_png` "shares no code with the other three", the cause
must be below all four. There were in fact **two independent causes**. Three
tests share one; `lib_png` had its own. Recording it because the inference was
reasonable and still cost a wrong search direction.

### Cause 1 — by-value managed-record parameter aliases the caller (this fix)

Bisected from the repro, each step measured, never inferred:

    EcdsaP256Verify -> line 334 `u1b := BigToBytes(u1, 32)` -> inside
    BigToBytes, the single statement `a := q` -- a store into its BY-VALUE
    parameter `a: TBigInt`.

`AllocParam` stores a record of `RecSize <= 8` **INLINE in the parameter's own
slot** — a raw byte copy of the caller's handles that nobody retained, so the
callee's copy BORROWS them. Read-only use is fine. A store into the parameter
(`a := q`, ordinary by-value mutation) lowers to `IR_COPY_REC_MANAGED`, which
RELEASES the destination's old fields — i.e. releases the **caller's** handles.
The caller's dynarray is freed under it; the next read gets a recycled block.
Wrong values first, the write-after-free segfault later and elsewhere.

**Fix** (`compiler/parser.inc`, the one place record params are forced by-ref):
a record with managed fields joins the `RecSize > 8` and CORBA-interface cases
and is passed **by reference** at any size. That puts it on the >8-byte path,
which was already correct — `IRLowerCallArg` makes a private temp and fills it
with `IR_COPY_REC_MANAGED`, so the copy OWNS its fields and the callee's stores
release the temp's handles, never the caller's. One condition, at the existing
decision point, with the CORBA fat-pointer case right beside it as precedent.

**It is not an arm32 bug.** The trigger is pointer-width dependent: `TBigInt`
(Boolean + dynarray handle) is 16 bytes on 64-bit — already by-ref, correct —
but 8 bytes on 32-bit. A record that is <= 8 bytes on x86-64 too (a lone
dynarray or string field) corrupts there identically. **Measured on x86-64,
arm32, aarch64 and riscv32**; the reduction is 30 lines with no libraries.

A first attempt forced the private copy in `IRLowerCallArg`'s `needTemp`
instead. That passes the temp's ADDRESS, which contradicts the inline-slot ABI
for <= 8-byte records — the callee then read its parameter as garbage and the
caller's frame was corrupted. Reverted; the ABI decision belongs at the one
place that makes it, not at the call site.

**Verified:** `lib_ecdsa_p256`, `lib_rsa`, `lib_rsa_pss` now produce output on
arm32 identical to x86-64 (previously SIGSEGV). The ticket's own 13-line repro
survives all 3 calls. Locked in as
`test/test_record_byvalue_managed_small.pas`, which reproduces the defect on
x86-64 too, so it does not depend on a cross target to have teeth; output is
byte-identical to FPC.

### Cause 2 — `lib_png`: dynamic-array assignment, filed separately

Bisected the same way:

    lib_png -> PngDecodeRGBA -> InflateZlib -> InflateRaw -> ReadBits
            -> gData[bytePos], gData a module-global TByteArray

and reduced to seven lines with no units: `b := a` on a **dynamic** array
segfaults on arm32 and riscv32. `IR_STORE_SYM` has no dyn-array arm in those
backends, and they carry no dynamic-array ARC machinery at all — no retain, no
release, no scope-exit cleanup. That is a structural port, not a patch, and the
**pinned** compiler crashes identically, so it is not recent. Filed as
`bug-a-arm32-dynamic-array-assignment-has-no-store-arm` (urgent, prio 75) with
the full reduction chain. `lib_png` stays red on arm32 until that lands; the
other three are green.

**Gate:** `testmgr --tier quick` 15/15 green; `tools/selfhost_fixedpoint.sh`
converges in 2 rounds from `pinned` and agrees with `compiler/pascal26`.
`tools/lib_cross_sweep.sh` run before and after the change and diffed, since a
record-param ABI change has wide blast radius. (`gate.sh quick`'s inline
one-pass fixedpoint false-REDs on any codegen change — see
`bug-t-gate-sh-fixedpoint-does-not-iterate`.)

## Log
- 2026-08-05 — resolved, commit 7d8c4ce6c.

### Cross-sweep, before and after (record-param ABI = wide blast radius)

`tools/lib_cross_sweep.sh` (101 lib tests x i386/arm32/aarch64) run on `pinned`
and on the fixed compiler, rows diffed. **42 failing rows -> 32. No
regressions.**

Cleared outright (12): `lib_ecdsa_p256` arm32+i386, `lib_rsa` arm32+i386,
`lib_rsa_pss` arm32+i386, `lib_classes` arm32+i386, `lib_bignum_ops` i386,
`lib_p256field` i386, `lib_x509` i386 build, `lib_http_pool_concurrent` i386.

Improved rather than cleared:
- `lib_x509` i386: **BUILDFAIL -> builds and runs**, one line off.
- `lib_x509` arm32: SIGSEGV (rc 139, 6 lines) -> rc 0, one line off.
  The surviving `chain-ok=FAIL` is PRE-EXISTING and cross-target-wide — it was
  already failing on aarch64 in the baseline, and is only more visible now that
  the tests get that far. Not caused by this fix; not in this ticket's scope.

The i386 build failures clearing is a side effect worth naming: i386 rejects
non-ordinal/pointer parameters ("only ordinal/pointer parameters supported
yet"), and a managed record is now a POINTER param, so eight tests that could
not compile for i386 at all now do.

Two rows in the "new" column, neither a regression:
- `lib_dns_cache_facade` arm32 — DNS `ETIMEDOUT` (`c2=-110`). `pinned` and the
  fixed compiler flake identically over repeated runs; the baseline had the same
  signature on i386. Network, not codegen.
- `lib_x509` i386 — the BUILDFAIL->DIFF improvement above.
