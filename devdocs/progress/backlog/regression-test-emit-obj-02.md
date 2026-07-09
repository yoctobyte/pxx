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

## Triage 2026-07-09 (cfront-agent, A+B+C) — NOT a compiler regression; Track T harness bug
Root-caused. The compiler is innocent and my SHA (c53553f2) is a false attribution:
- `make test-emit-obj` is GREEN at HEAD; `test-emit-obj#00` (the riscv32 .o compile
  + all readelf checks) is GREEN under testmgr; self-host byte-identical.
- The RED is only `#02`, whose log is `ld: cannot find .../test_emit_obj_rv.o`.

**Cause = testmgr `split_jobs` + per-PID scratch.** The emit-obj recipe COMPILES
`test_emit_obj_rv.o` (Makefile:3280) and LINKS it much later (the riscv `ld`
check, Makefile:3300-3303). `split_jobs` starts a new job at each compile that
follows a check, so the rv.o compile lands in `#00` while the ld-link lands in
`#02`. `RUN_TMP = /tmp/testmgr-scratch-<getpid()>` is PER PROCESS, so when `#00`
and `#02` run in different worker processes they get different scratch dirs and
`#02`'s ld can't see `#00`'s rv.o. It is FLAKY (green when they co-locate), which
is why it flipped at c53553f2 with no relevant code change (23c8286d was green).
Same class as the known borg shared-/tmp parallel race.

**Fix (Track T):** either keep the emit-obj recipe ATOMIC in split_jobs (it has
cross-line file deps: compile in one line, link in another), or make the ld-link
jobs depend on the compile job AND share its scratch (declare a dep like the
prologue path already does, or emit each `.o` inside the job that links it). Not
fixed here — testmgr.py is Track T's lane. Reassign to Track T.
