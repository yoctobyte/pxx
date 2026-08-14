---
track: A
prio: 75
type: bug
summary: "test_asm_avx gates on AVX + OSXSAVE + XCR0 (and FMA separately, correctly) but NOT on AVX2 — while every `vbroadcastsd ymm, xmm` it uses is the REGISTER-source form, which is AVX2. Only the memory-source form is AVX1. On an AVX1-only CPU the gate passes and the first vbroadcastsd is #UD. Master is RED on plexus (Ivy Bridge). The compiler is fine; the guard has one gap."
status: done
owner: agent-AN
---

# `test_asm_avx` gates on AVX but executes an AVX2 instruction

- **Type:** bug (test guard) — **Track A** (`test/test_asm_avx.pas`, from
  `feature-inline-asm-xmm-operands` phase 4).
  Found and diagnosed by Track T 2026-08-14; **T owns the tool, never the bug.**
- **Master is RED**: `test-asm#src:test/test_asm_avx.pas`, native tier, plexus.

## Reproduce (compiler rebuilt at HEAD)

```
$ ./compiler/pascal26 test/test_asm_avx.pas /tmp/avx26   # compiles clean
$ /tmp/avx26
Illegal instruction (core dumped)                        # rc 132
```

Faulting instruction, from gdb:

```
Program received signal SIGILL, Illegal instruction.
=> 0x40d2f6:	vbroadcastsd %xmm1,%ymm0
```

## The gap, exactly

The test's header reasoning is right and unusually careful — it gates on three
things and explains why each matters:

| checked | leaf |
|---|---|
| AVX | leaf 1 ecx bit 28 |
| OSXSAVE | leaf 1 ecx bit 27 |
| XCR0 SSE + YMM state | xgetbv bits 1, 2 |

and it checks **FMA separately and correctly** (leaf 1 ecx bit 12 → `FmaUsable`,
used to guard the FMA block at line 177).

**What is missing is AVX2** (leaf 7 ebx bit 5). And all 15 `vbroadcastsd` uses
are the **register-source** form:

```asm
vbroadcastsd ymm0, xmm1     { AVX2 — register source }
vbroadcastsd ymm0, [mem]    { AVX1 — memory source }
```

`vbroadcastsd` exists in AVX1, which is exactly why this is easy to miss — but
only with a *memory* source. The `ymm, xmm` form was introduced with AVX2. So on
an AVX1-only CPU the gate passes and the first broadcast is `#UD`, which is the
crash the header itself warns about:

> *"Executing an AVX instruction on a machine without it is #UD — a crash, not a
> failure message — so a test that assumed AVX would not report 'unsupported',
> it would take the whole suite down on older hardware."*

Correct in principle, one bit short in practice.

## The host

plexus is `Intel(R) Xeon(R) CPU E5-2620 v2` — Ivy Bridge-EP. Measured:

```
avx  yes    avx2 NO    fma NO    f16c yes    bmi2 NO
```

AVX2 and FMA both arrived with Haswell, so this box can never run those paths.
**Not a hardware problem to fix** — the watcher box is what it is, and the test's
own design says the answer is to gate.

## Fix — either works

1. **Add AVX2 to the gate**: leaf 7 (with ecx=0) ebx bit 5, and skip the
   broadcast paths without it. Consistent with how FMA is already handled.
2. **Use the memory-source form**, `vbroadcastsd ymm0, [x]`, which is AVX1 and
   needs no new gate. Changes what the test exercises, so option 1 is probably
   truer to intent.

**The compiler is not implicated.** The VEX emitter produced exactly the right
bytes — the header notes the encodings were verified against gas, 25
instructions, 110 bytes, byte-identical. This is only about which CPU may run
them.

## Gate

`test/test_asm_avx.pas` exits 0 on plexus (AVX yes, AVX2 no, FMA no) by skipping
what it cannot run and saying so, and still exercises the full set on a Haswell
or later box. Then the tstate red clears on the next native tier.

## Log
- 2026-08-14 — resolved, commit e000b3ea5.

## Resolution

Both fixes, each where it belongs — the ticket offered them as alternatives, but
they answer different halves and taking only one loses something.

**The arithmetic blocks broadcast from MEMORY** (`vbroadcastsd ymm0, a`), which
is AVX1. So the coverage that was the point of the test — the L bit over four
lanes, `vcmppd` + `vmovmskpd` proving mask 15, the non-destructive-source check,
the 0F38 map — still RUNS on plexus rather than being skipped. Option 1 alone
would have made the whole test a no-op on the one box that found the bug.

**The register-source form gets its own block behind a real AVX2 gate**
(`Avx2Usable`: leaf 7 subleaf 0, ebx bit 5, with a `maxLeaf >= 7` guard first —
asking for a leaf above the maximum returns the highest leaf's data, a wrong
answer rather than zeros). That keeps `vbroadcastsd ymm, xmm` executed where it
is legal, which is what the encoder work was for.

Encodings confirmed against gas, both forms:

```
gas   c4 e2 7d 19 05 34 12 00 00   vbroadcastsd 0x1234(%rip),%ymm0
gas   c4 e2 7d 19 c1               vbroadcastsd %xmm1,%ymm0
pxx   c4 e2 7d 19 04 25 <abs32>    (memory, SIB-absolute)
pxx   c4 e2 7d 19 c1               (register)
```

Same VEX prefix, same opcode; only the addressing form differs. The compiler was
never implicated and is unchanged.

Verified: passes on this box (AVX2 + FMA present — every block runs), and passes
with `Avx2Usable`/`FmaUsable` forced False, which is plexus's shape: `asm avx
ok`, rc 0, with the five AVX1 blocks still executing. Gate green
(self-host fixedpoint + `--tier quick`).
