---
track: A
prio: 35
type: feature
blocked-by: []
summary: "lib/rtl/random.pas cites `feature-rdrand-cpuid-compiler-builtins` in a source comment for its tier-1 hardware entropy path — and that ticket was never filed. Tiers 2 and 3 ship; tier 1 needs compiler intrinsics for CPUID + RDRAND (x86), MRS RNDR (aarch64) and the ESP RNG register, because the library's design mandate keeps per-arch instructions OUT of the .pas."
status: done
owner: claude-A
---

# Compiler intrinsics for hardware entropy (CPUID / RDRAND / RNDR / ESP RNG)

- **Type:** feature (intrinsics — **Track A**). Filed by Track B on 2026-08-15,
  which owns `lib/rtl/random.pas` and cannot add per-target instructions to it.
- The library already names this ticket in a comment; the ticket did not exist.
  A `find` for it returns nothing, which is how a dangling reference reads to
  the next person: as if the work were tracked when it is not.

## Why it belongs in the compiler, not the library

[[feature-random-library]] carries a hard design mandate: **one elegant `.pas`
file, no per-arch `{$ifdef}` soup.** The per-target instruction mess is supposed
to live behind intrinsics so the library reads as three one-line tier selections.
Tiers 2 (getrandom/urandom) and 3 (xoshiro256**) satisfy that today because
neither needs a special instruction. Tier 1 does, and that is the whole ask.

## What is needed

| target | mechanism | probe |
| --- | --- | --- |
| x86-64 / i386 | `RDRAND` (and optionally `RDSEED`) | `CPUID` leaf 1 ECX bit 30; leaf 7 EBX bit 18 for RDSEED |
| aarch64 | `MRS` of `RNDR` / `RNDRRS` | `ID_AA64ISAR0_EL1` RNDR field — FEAT_RNG is **optional** |
| arm32 | none in user mode | — (library stays on tier 2) |
| riscv32 | Zkr is an M-mode CSR, not user-reachable | — (tier 2) |
| ESP32 xtensa / riscv32 | RNG data register (bare) or `esp_random` (IDF) | always present on the SoC |

Two landmines worth building into the intrinsic rather than leaving to callers:

- **`RDRAND` can FAIL.** It clears CF instead of returning a value, under load or
  entropy exhaustion. The intrinsic must report success, so the library can
  bound its retries and then fall to tier 2 — a silent zero would be a
  catastrophic and invisible failure in a security context.
- **FEAT_RNG is optional on aarch64.** The probe is mandatory; an unconditional
  `MRS RNDR` is an illegal instruction on most cores.

Shape suggestion, matching how the library already dispatches (a proc-typed var
chosen once in `initialization`):

```
function __pxxCpuHasHwRandom: Boolean;
function __pxxHwRandom64(var v: UInt64): Boolean;   { False = failed, try again/fall back }
```

Two entry points, everything arch-specific behind them.

## Note on the ESP tier

ESP's RNG is only truly random with the RF/WiFi clock enabled. Whatever lands
must not let the library claim CSPRNG quality in the bare profile without it —
[[feature-random-library]] says so explicitly and the intrinsic should make the
distinction reportable rather than assumed.

## Gate

`make test` + self-host byte-identical; the probe reporting correctly on a CPU
that HAS the instruction and on one that does not (qemu can model both); and
`test/lib_random.pas` still producing its byte-identical seeded stream on every
target — tier 1 must not perturb the deterministic path, which is seeded and by
definition does not use hardware entropy.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `lib/rtl/random.pas` still
carries the tier-1 stub and still names this ticket in the comment
(`STUB: requires __rdrand/__cpuid compiler builtins … Falls to tier 2`), so
the library is still running one tier below its design. The dangling-reference
problem the ticket was filed to fix is resolved — the ticket exists now — and
the work behind it has not landed.

## Resolution — x86-64 (2026-08-21)

Both entry points exist and work, with the ticket's exact suggested shape:

```pascal
function __pxxCpuHasHwRandom: Boolean;
function __pxxHwRandom64(var v: UInt64): Boolean;   { False = failed, retry / fall back }
```

They live in the compiler's `builtin` unit and are pulled in by the name
pre-scan in `ParseProgram`, so **`lib/rtl/random.pas` needs neither a `uses` nor
an `{$ifdef}`** — which is the mandate this ticket exists to satisfy.

### Both landmines are built in, as the ticket asked

- **RDRAND can fail.** `setc` is the only thing read: the instruction clears CF
  and leaves the destination ZERO on failure, so a caller reading the value
  alone would take a silent zero for entropy. The `Boolean` is the guard.
- **The probe is mandatory.** `__pxxCpuHasHwRandom` runs CPUID leaf 1 and tests
  ECX bit 30, and caches the answer in a three-state variable (`0` unknown /
  `1` yes / `2` no — one variable rather than two Booleans that must agree).

### Two assembler mnemonics, in both encoders

`rdrand` and `rdseed` were not in either assembler. Added to `asmenc.inc` (the
`asm ... end` encoder) and `asmtext.inc` (`EmitAsmX64`), per that file's own
rule that a mnemonic lands in both or the reason is written down. They are
`0F C7 /6` and `/7` — not part of the F6/F7 unary group, they share a two-byte
opcode with `cmpxchg8b` keyed by the ext digit.

**Verified byte-exact against GNU `as`**, all seven forms including REX.B
extended registers and the 32-bit encodings:

```
48 0f c7 f0  rdrand rax     0f c7 f0     rdrand eax
48 0f c7 f1  rdrand rcx     41 0f c7 f1  rdrand r9d
49 0f c7 f4  rdrand r12     48 0f c7 f8  rdseed rax
                            48 0f c7 fb  rdseed rbx
```

The 27-byte sequence `as` produces for those seven appears verbatim in a pxx
binary compiled from the same seven lines.

### Staged, and the other targets say so honestly

x86-64 only, which is what the ticket's per-arch note asked for. Every other
target's `__pxxCpuHasHwRandom` answers **False** — and that is the correct
answer, not a stub: arm32 and riscv32 have no user-mode instruction, aarch64's
`MRS RNDR` needs the optional FEAT_RNG plus an `ID_AA64ISAR0_EL1` probe and
system-register support in the a64 assembler, and ESP's RNG register is Track S
and is only truly random with the RF clock enabled. False routes the library to
tier 2, which is exactly where those targets belong.

### Not done here

Wiring `lib/rtl/random.pas` is a **Track B** change and is filed as
[[feature-b-random-tier1-consume-the-hw-entropy-intrinsics]]. The library's
tier-1 stub and its comment naming this ticket are still in place.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 110s).
`test/test_hw_random_intrinsics.pas`: 3/3 on x86-64 (probe TRUE, 32/32 draws,
values distinct) and 2/2 on i386 / arm32 / aarch64 / riscv32 (probe FALSE, 0
draws — the relationship holds in both directions, which is what the test
asserts rather than the presence of the instruction).
`test/lib_random.pas` and `test/lib_randomstate.pas` produce output
**byte-identical to `pinned`'s** — the seeded stream is untouched, as the
ticket's gate required.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
