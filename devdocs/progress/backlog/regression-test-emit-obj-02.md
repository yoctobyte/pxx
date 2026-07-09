---
prio: 70
---

# regression: test-emit-obj#02 red at c53553f21214 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-09T06:03:51Z

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#02'` at c53553f2121456f40c70e519982a8427c4f313ac

## Range
bad `c53553f21214`, last good `c53553f21214`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2236388/test_emit_obj_xt_windowed.o  [code=30416B  data=72B  bss=74468B  procs=48]
/home/rene/.espressif/tools/riscv32-esp-elf/esp-15.2.0_20251204/riscv32-esp-elf/bin/../lib/gcc/riscv32-esp-elf/15.2.0/../../../../riscv32-esp-elf/bin/ld: cannot find /tmp/testmgr-scratch-2236388/test_emit_obj_rv.o: No such file or directory
collect2: error: ld returned 1 exit status

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
