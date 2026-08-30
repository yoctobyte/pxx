---
prio: 70
track: A+S
status: done
---

> **Track corrected P -> A+S by frank-coordinator, 2026-08-30.** The watcher guesses
> from the test source, and `external name 'ext_aliased_link'` is a Pascal directive, so
> P is the honest guess. But **the failure is target-specific and a frontend bug cannot
> be**: the log tail shows `test_emit_obj_rv.o`, `_xt.o` and `_xt_windowed.o` all emitted
> `ok`, and only the **riscv32 link** fails with `undefined reference to ext_aliased_link`.
> One frontend produced every one of those objects from the same source. So the defect is
> below the frontend — object/symbol emission or the cross link recipe — which is A, with
> S because the failing toolchain is riscv32-esp-elf.
>
> This is a retrack, NOT a diagnosis. Do not read the reason above as a root cause: it
> bounds where the cause can be, and nothing more. In particular the linker naming
> `AddUp` as the referencing function is where the reference IS, not where the bug is.

> **origin/master has advanced 33 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/test_emit_obj.pas red at bfec13534396 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T00:49:48Z
- **Test source:** test/test_emit_obj.pas

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/test_emit_obj.pas'` at bfec135343961cc33559d058bccc63e4c871eceb

## Range
> **The named sha `bfec13534396` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `bfec13534396`, last good `6a19b5333e07`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
(.text+0x3b418): undefined reference to `ext_aliased_link'
collect2: error: ld returned 1 exit status
(tail)
ok: /tmp/testmgr-scratch-3214473/test_emit_obj_rv.o  [code=242916B  data=2016B  bss=42288B  procs=168]
ok: /tmp/testmgr-scratch-3214473/test_emit_obj_xt.o  [code=210060B  data=1624B  bss=42288B  procs=173]
ok: /tmp/testmgr-scratch-3214473/test_emit_obj_xt_windowed.o  [code=186883B  data=1624B  bss=42288B  procs=173]
/home/seven/.espressif/tools/riscv32-esp-elf/esp-15.2.0_20251204/riscv32-esp-elf/bin/../lib/gcc/riscv32-esp-elf/15.2.0/../../../../riscv32-esp-elf/bin/ld: /tmp/testmgr-scratch-3214473/test_emit_obj_rv.o: in function `AddUp':
(.text+0x3b418): undefined reference to `ext_aliased_link'
collect2: error: ld returned 1 exit status

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED — the recipe contradicted itself, and it was never target-specific

Reproduced at HEAD `f19e16b67bad` (a real fixedpoint, `converged after 1 round`),
deterministic.

**Cause:** `1a7658326 fix(A): --emit-obj and --shared honour \`external name\`,
via one resolver` — a correct commit. It made the object reference the LINK name
and added two assertions demanding exactly that:

```
readelf -sW ... | grep -q 'UND ext_aliased_link'
! readelf -sW ... | grep -q 'ext_alias_decl'
```

Thirty-five lines further down the **same recipe**, the inline `@printf` that
generates `test_emit_obj_shim.c` defines only `ext_notify`. So the recipe asserts
a symbol must be undefined and then links without providing it. The link step
could only start failing once the compiler started getting it right.

**Fix:** one line in that shim — `void ext_aliased_link(int v) { (void)v; }`.
Verified against the real toolchains on this box: riscv32, xtensa and
xtensa-windowed all link. The readelf assertions are kept; they are the ticket's
subject. Deleting the link check instead would have preserved the subject while
discarding the only thing that proves the emitted object is usable.

### The retrack reason was false, and the way it was false is the finding

The ticket was retracked P → A+S on the argument that *"the log shows `_rv.o`,
`_xt.o` and `_xt_windowed.o` all emitting ok and only the riscv32 link failing,
so the cause is below the frontend but target-specific."* Measured:

| claim | measurement |
| --- | --- |
| three targets emitted `ok`, one link failed | those `ok:` lines are object **emissions**, not links |
| the failure is riscv32-specific | all three objects carry `UND ext_aliased_link` **identically** |
| xtensa links fine | `_xt.o` + the old shim fails the same way, at `.text+0x3340c` vs riscv32's `+0x3b418` |

The xtensa link **never ran**: make aborts at the riscv32 line. The single-target
red meant *the runner stopped*, not *one target is special* — a truncation
artefact read as a discriminator.

This is the same class as
[[bug-a-halt-n-exits-zero-on-hosted-xtensa]]'s green row, from the other side:
**the shape of the evidence was produced by the harness, not by the defect.**
There a pass meant "the row asserted the wrong observable"; here a
one-target failure meant "make stopped at the first of three". Both invite a
target-specific story, and in both cases the *second data point* is what kills
it. The retrack still reached the right lane — by luck, not by method, which is
the outcome that does not self-correct, because the destination keeps looking
like evidence for the argument.

### Bound

Object-level plus a real link, at `f19e16b67bad`, with
`riscv32-esp-elf-gcc 15.2.0` and `xtensa-esp32s3-elf-gcc 15.2.0` from
`~/.espressif`. The 23-commit bisect range was never used: the cause was found by
reading the recipe against its own assertions, so nothing here rules on the other
22 commits — only on this failure.
- 2026-08-30 — resolved, commit 2d875d40d.
