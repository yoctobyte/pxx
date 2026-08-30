---
prio: 70
track: A+S
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
