---
prio: 70
status: done
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

## TRIAGE 2026-08-16 — two roots, both named; 15 of 17 already green

Not one root cause but two, and the split falls exactly on "does it reproduce
on the PINNED binary".

**Root 1 (mine, FIXED at e10590243) — 15 jobs.** The three nilpy `encode` /
`intrinsic_result_chain` rows and all twelve uforth shards. Two defects, both
introduced by adding the Python method set to `TPyBytes`:

- a pylib name collision — my absolute-index `PyBytesPut` shadowed the existing
  cursor-advancing one at every call site of `pystr_encode_enc_err`, so
  `"hi".encode("latin-1")` came back `b'i\x00'`. Renamed to `PyBytesSet`.
- a parse gap the method set made universal —
  [[bug-nilpy-a-chained-method-on-a-runtime-dispatched-result-is-refused]]:
  a second `.method()` on a runtime-dispatched result was `unexpected token`,
  because the dispatcher returns an AN_TERNARY and the suffix loops required
  AN_CALL. uforth.py chains string methods everywhere, which is why twelve
  shards went with it.

Verified at HEAD: uforth.py compiles, the smoke run answers `3 3`, and the
`stringtest` word set is byte-identical to CPython again.

**Root 2 (NOT mine) — 2 jobs.** `test_nilpy_math_domain_errors` and
`test_nilpy_math_log` reproduce identically on the PINNED binary and bisect to
Track B's `11321a09c` (Power and LogN, 26x each). Filed as
[[bug-b-power-lost-an-ulp-on-a-half-integer-exponent]] — one genuine ulp
regression on `math.pow(2.0, 0.5)` plus one `.expected` row that is stale
because the rewrite CORRECTED it. Those two rows stay red until Track B lands
that ticket; no further cascade signal is needed for them.

Closed: the cascade is triaged and its larger root is fixed and pushed. The
residual is one owned ticket in another lane.

## Log
- 2026-08-16 — resolved, commit 1d9f627c7.
