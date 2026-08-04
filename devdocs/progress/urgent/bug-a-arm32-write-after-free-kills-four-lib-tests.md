---
summary: "arm32 only: WRITE AFTER FREE segfaults FOUR lib tests (ecdsa, rsa, rsa_pss, png); reduces to 'call EcdsaP256Verify twice'; -O-independent, x86-64/aarch64 clean"
type: bug
track: A
prio: 75
---

# arm32: a write-after-free segfaults four lib tests (reduces to two calls)

- **Type:** bug — Track A (arm32 codegen / managed-value lifetime).
  **Lane is a judgement call**: the source is `lib/rtl/ecdsa_p256.pas` (Track B),
  but identical source is correct on x86-64 and aarch64, and the fault is
  memory lifetime rather than arithmetic — so it is filed to A. Move it if the
  bisect says otherwise.
- **Status:** urgent
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
