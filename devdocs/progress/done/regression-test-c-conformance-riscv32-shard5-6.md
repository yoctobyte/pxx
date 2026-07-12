---
prio: 70
---

# regression: test-c-conformance-riscv32#shard5/6 red at 96b6bac331d9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T17:39:05Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-riscv32#shard5/6'` at 96b6bac331d9d8b9c838d0055a8e3841157314f1

## Range
bad `96b6bac331d9`, last good `96b6bac331d9`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00204.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00204.c.expected	2026-07-07 21:11:07.000000000 +0200
    +++ /tmp/pxx_c_conformance.217888/out.txt	2026-07-12 19:37:04.863368984 +0200
    @@ -102,58 +102,58 @@
     0
     abcd
     abcd0000
    -abcd00000000
    -abcd000000000000
test-c-conformance-riscv32: 35 pass, 1 fail, 0 skip (of 36)
test-c-conformance-riscv32: FAILURES: 00204.c(output)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-07-12 — resolved, commit 38d8cb5e.

**Triage:** not a regression. `bad == last good == 96b6bac331d9`, 0 commits in
range — this job was newly *enrolled* at `eb63555d` (cross-conformance matrix), so
this is a first measurement of a pre-existing cross-target gap, not a break caused
by a commit in range. The underlying bugs are tracked in their owning lanes:
[[bug-c-generic-long-vs-int-on-32bit]] (00219), [[bug-c-lshift-promotion-aarch64]]
(00200), [[bug-c-struct-byval-varargs-32bit]] (00204). The tests are still red;
this stub is retired only because it duplicates those three.
