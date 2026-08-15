---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 17 jobs newly red at 343a52551808 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 17 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-15T22:24:34Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 343a52551808e14463db6ff315dc6d79b8624bfd

## Newly red jobs
- `test-nilpy#src:test/test_nilpy_encode.npy`
- `test-nilpy#src:test/test_nilpy_encode_decode_codecs.npy`
- `test-nilpy#src:test/test_nilpy_intrinsic_result_chain.npy`
- `test-nilpy#src:test/test_nilpy_math_domain_errors.npy`
- `test-nilpy#src:test/test_nilpy_math_log.npy`
- `test-uforth#core`
- `test-uforth#coreexttest`
- `test-uforth#coreplustest`
- `test-uforth#doubletest`
- `test-uforth#exceptiontest`
- `test-uforth#facilitytest`
- `test-uforth#filetest`
- `test-uforth#localstest`
- `test-uforth#memorytest`
- `test-uforth#searchordertest`
- `test-uforth#stringtest`
- `test-uforth#toolstest`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
