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
