---
prio: 70
---

# regression CASCADE: 60 jobs newly red at 25678cbdd57c (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host xeon).
  Untriaged. 60 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-01T02:56:33Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 25678cbdd57c6ec9ce3d529e995fe0cc57c3ab84

## Newly red jobs
- `test-asm#src:compiler/compiler.pas`
- `test-asm#src:test/hello.pas`
- `test-asm#src:test/test_asm_entry_global.asm`
- `test-asm#src:test/test_asm_extern.asm`
- `test-asm#src:test/test_asm_hello.asm`
- `test-asm#src:test/test_asm_loop.asm`
- `test-asm#src:test/test_asm_mvp.asm`
- `test-asm#src:test/test_asm_obj.asm`
- `test-asm#src:test/test_asm_so.asm`
- `test-asm#src:test/test_asmcore_aarch64.pas`
- `test-asm#src:test/test_asmcore_arm32.pas`
- `test-asm#src:test/test_asmcore_i386.pas`
- `test-asm#src:test/test_asmcore_riscv32.pas`
- `test-asm#src:test/test_asmcore_x64.pas`
- `test-asm#src:test/test_asmcore_xtensa.pas`
- `test-core#src:compiler/compiler.pas@2`
- `test-core#src:test/crtl_lfs64_aliases_b234.c`
- `test-core#src:test/test_advanced_records_b268.pas`
- `test-core#src:test/test_anonymous_record.pas`
- `test-core#src:test/test_asm_branch.pas`
- `test-core#src:test/test_asm_memr.pas`
- `test-core#src:test/test_asm_sizekw.pas`
- `test-core#src:test/test_byvalue_record_managed_copy.pas`
- `test-core#src:test/test_channel.pas`
- `test-core#src:test/test_dynarray_record_field.pas`
- `test-core#src:test/test_forin_record_enumerator_b355.pas`
- `test-core#src:test/test_getinterface_guid_b257.pas`
- `test-core#src:test/test_nilpy_html_tempfile.npy`
- `test-core#src:test/test_nilpy_module_first_import.npy`
- `test-core#src:test/test_nilpy_raw_string_set.npy`
- `test-core#src:test/test_nilpy_re.npy`
- `test-core#src:test/test_promoint.pas`
- `test-core#src:test/test_promoint_overflow.pas`
- `test-core#src:test/test_ptr_deref_vararg.pas`
- `test-core#src:test/test_record_ctor_expr_tails_b333.pas`
- `test-core#src:test/test_record_rules_ok.pas`
- `test-core#src:test/test_setlength_managed_field.pas`
- `test-core#src:test/test_textfile.pas`
- `test-core#src:test/test_textfile_in_unit.pas`
- `test-core#src:test/test_types_point_methods_b269.pas`
- `test-smoke#src:test/test_mutex.pas`
- `test-threads#src:test/test_async_parallel_compat.pas`
- `test-threads#src:test/test_atomic64.pas`
- `test-threads#src:test/test_atomic_counter.pas`
- `test-threads#src:test/test_condvar.pas`
- `test-threads#src:test/test_critsec_once.pas`
- `test-threads#src:test/test_event.pas`
- `test-threads#src:test/test_mutex.pas`
- `test-threads#src:test/test_palthread.pas`
- `test-threads#src:test/test_parallel_for.pas`
- `test-threads#src:test/test_parallel_for_capture.pas`
- `test-threads#src:test/test_parallel_for_capture_string.pas`
- `test-threads#src:test/test_parallel_for_lang.pas`
- `test-threads#src:test/test_parallel_reduction.pas`
- `test-threads#src:test/test_parallel_writeln_atomic.pas`
- `test-threads#src:test/test_thread_writeln_interleave.pas`
- `test-threads#src:test/test_tthread.pas`
- `test-threads#src:test/test_tthread_final.pas`
- `test-threads#src:test/test_tthread_sync.pas`
- `test-threads#src:test/test_tthread_terminate.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
