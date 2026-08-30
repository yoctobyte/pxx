---
sha: dbcacce2fd79806d5e3fd388e6329cbf9397df00
parent_tested: c1c32faf656212a0a23c5025229e6b2e5640ab93
date: 2026-08-29T21:25:32Z
host: plexus
tier: native
wall: 469.4
scale: 1.0
verdict: RED
compiler_sha256: 2ef7053d0926d8b9dca25b44e67545818affa82889b13de05bda88479660668d
skips: 0
skip_holes: 0
---

> **-O3 IS UNTESTED ON THIS TREE.** The newest `opt` sweep is 1d0h old and ran at `eb1b200ee92f` (GREEN). `opt` is disjoint from `native`, so no optimisation level above the default has seen this sha.

## STILL-RED
- test-core#src:test/test_mgmt_operators.pas — test/test_mgmt_operators.pas test/test_mgmt_operators.expected +5
  - `ok: $TMP  [code=297752B  data=24744B  bss=75692B  procs=730] | FAIL: an array of a managed record compiled`

## first failure: test-core#src:test/test_mgmt_operators.pas — test/test_mgmt_operators.pas test/test_mgmt_operators.expected +5 (fail)
repro: `tools/testmgr.py --tier native --job 'test-core#src:test/test_mgmt_operators.pas'` at dbcacce2fd79806d5e3fd388e6329cbf9397df00
```
ok: /tmp/testmgr-scratch-1600431/test_mgmt_operators26  [code=297752B  data=24744B  bss=75692B  procs=730]
FAIL: an array of a managed record compiled

```
