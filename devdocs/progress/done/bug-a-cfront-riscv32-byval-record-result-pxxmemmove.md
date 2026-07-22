---
prio: 70
---

# bug: C→riscv32 by-value record result emits PXXMemMove but the C compile never injects builtinheap

- **Type:** bug (Track A — C frontend × riscv32 codegen × builtin injection).
  Filed by Track T from the overnight cascade; T owns the tool, not the bug.
- **Found:** 2026-07-20 (cascade at ~20:45); root-caused 2026-07-21.
- **Roots the cascade** `regression-cascade-6906a3416548` (18 riscv32 jobs).

## Symptom
Every riscv32 conformance shard (0-6) and every riscv32 cross-run job went red
in one sweep and stayed red across every full run since. **riscv32-only** —
arm32 / aarch64 / i386 pass the same jobs.

## Deterministic repro (reproduced on borg 2026-07-21, HEAD de2669f2)
```
tools/testmgr.py --tier full --job 'test-riscv32#src:test/ccross_args.c@1'
```
fails with:
```
pascal26:429: error: compiler error: PXXMemMove not found
  near:     end  >>> function PalIn6Any
```
i.e. `./compiler/pascal26 --target=riscv32 test/ccross_args.c ...` cannot
compile a C function that returns a record (struct) by value.

## Root cause
`PXXMemMove` is defined in `compiler/builtin/builtinheap.pas` (line 158). The
riscv32 by-value-record-result lowering does `FindProc('PXXMemMove')` and
`Error('compiler error: PXXMemMove not found')` if it is absent
(`compiler/symtab.inc:6041/6120`, mirrored in `ir_codegen_arm32.inc`). When the
**Pascal** frontend compiles for riscv32, builtinheap is in scope and the proc
is found — that path is done and verified (`feature-riscv32-record-function-results`,
2026-06-23). When the **C** frontend compiles for riscv32, builtinheap is NOT
injected, so the same codegen path hits the missing proc.

So: C-frontend + riscv32 + by-value record result → PXXMemMove not found. The
Pascal path is fine; the gap is the C compile not providing the builtin its
own riscv32 record-return codegen depends on.

## Newly EXERCISED, not newly introduced
No riscv32 / symtab / builtin / codegen commit landed in the cascade window —
the suspects (`18790cf7`, `862bb4fe`) are weeks old, and the code just before
the first red is uforth/nilpy/docs. The C cross-conformance matrix
(`b385a381`) added riscv32 coverage earlier; a corpus/shard/timeout shift
(candidate: `99736aca` per-program timeout rescale) appears to have newly
routed a record-returning C program onto riscv32. The underlying gap has
existed since C-frontend riscv32 record-return was reachable; nothing regressed
in behaviour, coverage caught up to it.

## Why arm32 passes (needs confirming in the fix)
arm32 uses the identical `FindProc('PXXMemMove')` pattern
(`ir_codegen_arm32.inc:3113`) yet its C conformance is green. Either arm32 C
compiles DO inject builtinheap (then riscv32 should mirror that), or no arm32
conformance program in the current sharding returns a record by value (then the
gap is latent there too, not fixed). The fix should establish which, so it does
not just move the red to arm32 on the next corpus reshuffle.

## Fix direction (Track A's call)
Ensure the C-frontend riscv32 (and by symmetry arm32/xtensa) record-return path
has `PXXMemMove` available — inject builtinheap into the C compile when the
record-copy/record-result lowering can fire, or provide the memmove primitive
the C path can always resolve. Do NOT special-case the one failing program.

## Scope / handoff
Track A (shared `symtab.inc` + riscv codegen + builtin injection). The overnight
`regression-cascade-6906a3416548` stub is superseded by this ticket; the second
stale stub `regression-cascade-3d46e52fc733` is the OLD (2026-07-20 early, the 461-job flood sha) qemu-collapse
event and unrelated — safe to reject.

## Also covers test-lua-cross (2026-07-21)

`test-lua-cross` builds lua for all four cross targets (`aarch64 arm32 i386
riscv32`); the job is red because its **riscv32** leg fails on the same
`PXXMemMove not found` — lua's C hits a by-value struct return under
`--target=riscv32`. So `test-lua-cross` in the 6906a341 cascade is NOT a
separate failure; it is this bug under a non-riscv-looking job name. It will go
green with the fix. Current real red surface from this one root: 17
`test-*riscv32*` jobs + `test-lua-cross` = 18, matching the cascade exactly.

## Log
- 2026-07-22 — resolved, commit 40eff645.
