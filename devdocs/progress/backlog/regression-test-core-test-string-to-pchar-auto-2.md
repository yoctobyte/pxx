---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_string_to_pchar_auto.pas /tmp/string_to_pchar_auto26`, which names `test/test_string_to_pchar_auto.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_string_to_pchar_auto.pas at f33eeb316d43 in step 1/2, `./compiler/pascal26 test/test_string_to_pchar_auto.pas /tmp/string_to_pchar_auto26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-05T04:32:10Z
- **Test source:** test/test_string_to_pchar_auto.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_string_to_pchar_auto.pas`.
  ```
  ./compiler/pascal26 test/test_string_to_pchar_auto.pas /tmp/string_to_pchar_auto26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_string_to_pchar_auto.pas'` at f33eeb316d4362d85006b8b0dae50990f28fcce0

## Range
> **The named sha `f33eeb316d43` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f33eeb316d43`, last good `9f0bfc4a4bd3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined
(tail)
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-10-09 — the borg watcher saw `test-core#src:test/test_string_to_pchar_auto.pas` GREEN at 39225dde3632 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-string-to-pchar-auto-2`, not `regression-test-core-test-string-to-pchar-auto`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
