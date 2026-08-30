---
prio: 70
track: A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance-aarch64#shard0/6 red at b695bcb4b192 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T14:03:47Z
- **Test source:** compiler/.pascal26.fixedpoint tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard0/6'` at b695bcb4b19264847cedc6c01678d4e298d14cfb

## Range
> **The named sha `b695bcb4b192` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b695bcb4b192`, last good `4d3f8a4eac00`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
self-host fixedpoint: verified — 1 round(s), 82583d52f672 --shard 0/6
FAIL 00175.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00175.c.expected	2026-08-29 16:16:00.000000000 +0000
    +++ /tmp/pxx_c_conformance.3650240/out.txt	2026-08-30 14:03:15.227717970 +0000
    @@ -4,9 +4,9 @@
     int: 97
     int: 98
     int: 99
    -float: 97.000000
    -float: 98.000000
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00175.c(output)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
