---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 17 jobs newly red in 8a5e4abb3..426b90021 (3 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 17 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-20T22:12:26Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Range
> **The named sha `426b90021634` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `426b90021634`, last good `8a5e4abb3242`, **3 commit(s) in range** (1 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `cd7e4aae3f44` feat(A): the main thread gets its TLS block at the ELF entry point

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 426b90021634e43b6bce171691dd4f772767feb1

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-core#src:test/test_ansistring_cast_extern_pchar.pas`
- `test-core#src:test/test_ansistring_cast_fnptr.pas`
- `test-core#src:test/test_c_dlopen.pas`
- `test-core#src:test/test_c_gtk_call.pas`
- `test-core#src:test/test_c_gtk_types.pas`
- `test-core#src:test/test_c_gtk_window.pas`
- `test-core#src:test/test_cdecl_indirect.pas`
- `test-core#src:test/test_dynlib.pas@2`
- `test-core#src:test/test_exception_unhandled.pas@1`
- `test-core#src:test/test_exception_unhandled.pas@3`
- `test-core#src:test/test_multithreading.pas@1`
- `test-core#src:test/test_nilpy_c_pointer.npy`
- `test-core#src:test/test_shared_object.pas`
- `test-core#src:test/test_sqlite_crud.pas`
- `test-core#src:test/test_sqlite_crud_autotyped.pas`
- `test-core#src:test/test_sqlite_crud_lazy.pas`
- `test-core#src:test/test_string_to_pchar_auto.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
