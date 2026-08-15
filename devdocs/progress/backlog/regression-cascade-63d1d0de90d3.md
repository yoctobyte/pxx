---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 29 jobs newly red at 63d1d0de90d3 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 29 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-15T14:48:16Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 63d1d0de90d3c135e6cc32dc6cb9f6fdfd1fa65c

## Newly red jobs
- `test-core#src:test/test_basic_comprehensive.bas`
- `test-core#src:test/test_c_cross_ns_arity_fail.pas`
- `test-core#src:test/test_c_crypt.pas`
- `test-core#src:test/test_c_define_const.pas`
- `test-core#src:test/test_c_dlopen.pas`
- `test-core#src:test/test_c_enum.pas`
- `test-core#src:test/test_c_gtk_call.pas`
- `test-core#src:test/test_c_gtk_types.pas`
- `test-core#src:test/test_c_gtk_window.pas`
- `test-core#src:test/test_c_header_case_sensitive_import.pas`
- `test-core#src:test/test_c_import.pas`
- `test-core#src:test/test_c_macro_soup.pas`
- `test-core#src:test/test_c_packed_aligned.pas`
- `test-core#src:test/test_c_preprocess.pas@1`
- `test-core#src:test/test_c_preprocess.pas@2`
- `test-core#src:test/test_c_slicea.pas`
- `test-core#src:test/test_c_struct_fields.pas`
- `test-core#src:test/test_c_struct_many.pas`
- `test-core#src:test/test_c_struct_tags.pas`
- `test-core#src:test/test_c_typedef.pas`
- `test-core#src:test/test_exception_unhandled.pas@3`
- `test-core#src:test/test_math_unit.pas@1`
- `test-core#src:test/test_nilpy_c_define_const.npy`
- `test-core#src:test/test_nilpy_c_pointer.npy`
- `test-core#src:test/test_shared_object.pas`
- `test-core#src:test/test_sqlite_crud.pas`
- `test-core#src:test/test_sqlite_crud_autotyped.pas`
- `test-core#src:test/test_sqlite_crud_lazy.pas`
- `test-core#src:test/test_string_to_pchar_auto.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
