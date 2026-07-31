---
prio: 70
---

# regression CASCADE: 17 jobs newly red at 110774a14648 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host xeon).
  Untriaged. 17 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-07-31T16:56:14Z
- **Root-cause suspects in the red set:** `fpc-bootstrap#src:compiler/compiler.pas`, `selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh`

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 110774a1464878920dcdf27d2afae7ca36dae219

## Newly red jobs
- `fpc-bootstrap#src:compiler/compiler.pas`
- `selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh`
- `test-asm#src:test/test_asm_so.asm`
- `test-core#src:examples/tk/facade_and_paths.npy`
- `test-core#src:examples/tk/import_in_body.npy`
- `test-core#src:examples/tk/shadow_format_except.npy`
- `test-core#src:test/cprintf_ll_b252.c@2`
- `test-core#src:test/test_c_define_const.pas`
- `test-core#src:test/test_c_gtk.pas`
- `test-core#src:test/test_c_gtk_call.pas`
- `test-core#src:test/test_c_gtk_types.pas`
- `test-core#src:test/test_c_gtk_window.pas`
- `test-core#src:test/test_nilpy_c_define_const.npy`
- `test-core#src:test/test_sqlite_crud.pas`
- `test-core#src:test/test_sqlite_crud_autotyped.pas`
- `test-core#src:test/test_sqlite_crud_lazy.pas`
- `test-core#src:test/test_string_to_pchar_auto.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

---

## REJECTED — false positive, not a regression (Track T, 2026-07-31)

All 17 jobs were red because of the **host**, not the commit. `110774a14648`
is a tstate-only commit (`tstate(borg): opt f2f1a3a9add8 done`) and touches no
code at all, so it cannot have caused a single one of these.

This was the **first run of a newly enrolled watcher box (xeon)**, and the reds
decompose into exactly two causes, both measured at the sha, both now closed:

**1. The suite tested the wrong binary (accounts for the two "root-cause suspects").**
A fresh watcher clone is seeded with `make seed-from-stable`, which *copies*
`stable_linux_amd64/default/pinned` onto `compiler/pascal26`. The copy lands with
a **newer mtime than `compiler/compiler.pas`**, so testmgr's `make compiler/pascal26`
reported "up to date" and never self-hosted. The whole 1098-job sweep ran against
the pinned binary rather than a compiler built from the checked-out sources.
`compiler/pascal26` was byte-identical to `pinned` and 13 minutes newer than the
sources — measured, not inferred.

`selfhost-fixedpoint` is the ONLY job that can see this, and it did its job
correctly: property 2 (the anti-Thompson agreement check) fired exactly as
designed. After `touch compiler/compiler.pas && make compiler/pascal26`, the
gate converges in 1 round and agrees. Not a bug — the gate working.

`fpc-bootstrap` is the separately ticketed, advisory FPC seed drift
(`urgent/regression-fpc-seed-drift-b1976-stale.md`). It is red on borg too; it
is red here for the same reason and is NOT part of this cascade.

**2. Missing host dev packages (the other 15).** Each verified fixed by
installing the package, at the same sha, with no code change:

| jobs | missing on xeon | fix |
|---|---|---|
| 4× `test_c_gtk*` | **gtk2** headers — `compiler/cpreproc.inc:2083` hardcodes `/usr/include/gtk-2.0/`, so gtk**3** does not satisfy it | `libgtk2.0-dev` |
| 5× sqlite / `test_string_to_pchar_auto` / `test_c_define_const` | `sqlite3.h` | `libsqlite3-dev` |
| 4× `examples/tk/*.npy`, `test_nilpy_c_define_const.npy` | tcl/tk headers | `tk-dev` `tcl-dev` |
| 1× `cprintf_ll_b252.c@2` (i386) | pxx emits a **dynamically linked** i386 ELF needing `/lib/ld-linux.so.2`; the box had no 32-bit runtime, so `execve` returned ENOENT and `sh` said "not found" | `libc6:i386` |

`test-asm#src:test/test_asm_so.asm` passes standalone at the same sha and needed
no package — a genuine flake, folded in by the cascade grouping.

**Kept as a record rather than deleted**: this is the concrete reproduction of
the known "phantom NEW-RED" complaint, and cause 1 is a real trap — the
*documented* fresh-box step silently makes every job test a stale compiler, and
only one job in the matrix can notice. Follow-ups filed separately:
`task-t-seed-from-stable-defeats-rebuild` and
`task-t-suppress-autoticket-until-host-baselined`.
