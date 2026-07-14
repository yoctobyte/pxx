---
prio: 50
---

# arm32: `lib_chacha20poly1305` segfaults — and it is NOT the riscv32 array-param bug

- **Type:** bug (cross target — arm32 backend)
- **Track:** A — core (arm32 backend)
- **Status:** backlog — opened 2026-07-14, split out of
  [[bug-riscv32-p256field-coredump]] during a board triage sweep.

## Symptom
```
./compiler/pascal26 --target=arm32 -Fulib/rtl test/lib_chacha20poly1305.pas /tmp/c
tools/run_target.sh arm32 /tmp/c     -> SIGSEGV (139)
```
x86-64 runs it clean.

## Why this is its OWN ticket
`bug-riscv32-p256field-coredump` assumed one root cause covered both 32-bit targets — a
missing deref on the WRITE side of an indexed `var` array parameter. Measured at HEAD:

| target  | the riscv32 ticket's var-array-param repro | lib_sha256 | lib_chacha20poly1305 |
|---------|--------------------------------------------|------------|----------------------|
| arm32   | **PASSES**                                 | **PASSES** | **SIGSEGV**          |
| riscv32 | fails (writes lost / crash)                | SIGSEGV    | SIGSEGV              |

**arm32 passes that repro.** So the riscv32 defect cannot be what crashes it here, and
fixing riscv32 will not fix arm32. That assumption is exactly what kept this bug invisible:
it was filed as collateral of another ticket instead of as a bug.

The `lib_sha256` PASS on arm32 is the useful lever — sha256 and chacha20poly1305 are both
32-bit-word crypto over arrays, so whatever differs between them is close to the cause.
chacha20poly1305 additionally uses: 64-bit counters/lengths, `QWord` arithmetic, and record
parameters (the Poly1305 state).

## Where to start
- Diff what chacha20poly1305 uses that sha256 does not — start with the 64-bit (`QWord`)
  paths and record-by-value/by-ref parameters, which is where arm32 has historically
  bitten ([[project_arm32_aggregate_stackargs_done]], [[project_arm32_alignment_landmine]] —
  arm32 needs 4-byte alignment and passes aggregates on the stack past 4 args).
- Bisect the unit: cut chacha20poly1305 down until the crash goes away.

## Gate
`make test-arm32` green + `lib_chacha20poly1305` runs and prints its 7 `=ok` lines on arm32.
