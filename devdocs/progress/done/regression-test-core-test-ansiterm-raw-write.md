---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 28 of 3, `NOTTY="$(printf 'write-through-pal\nsize FALSE 80 24\nraw round-trip survived\nkey 0')"; \ PTY="$(printf 'write-through-`, which names `test/test_cross_ansiterm_through_the_pal.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_ansiterm_raw_write.pas@1 at 124d83cf494b in step 28/3, `NOTTY="$(printf 'write-through-pal\nsize FALSE 80 24\nraw round-trip survived\nkey 0')"; \ PTY="$(printf 'write-through…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T13:24:12Z
- **Test source:** test/test_ansiterm_raw_write.pas tools/expect_same.sh +2
- **Failing step:** line 28 of 3 of the job's recipe; it names `test/test_cross_ansiterm_through_the_pal.pas tools/expect_same.sh tools/run_target.sh`.
  ```
  NOTTY="$(printf 'write-through-pal\nsize FALSE 80 24\nraw round-trip survived\nkey 0')"; \ PTY="$(printf 'write-through-pal\nsize TRUE 132 40\nraw round-trip survived\nkey 0')"; \ ./compiler/pascal26 test/test_cross_ansiterm_through_the_pal.pas /tmp/atpal26 >/dev/null; \ tools/expect_same.sh atpal26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_ansiterm_raw_write.pas@1'` at 124d83cf494b632ba178d7f3fbcacb888799bec3

## Range
> **The named sha `124d83cf494b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `124d83cf494b`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-977694/test_ansiterm_raw_write26  [code=315160B  data=30484B  bss=85052B  procs=822]
wasmtime not found (looked on PATH and in ~/.local/bin)
expect_same: MISMATCH [atpal/wasm32]
--- expected
+++ actual
@@ -1,4 +1 @@
-write-through-pal
-size FALSE 80 24
-raw round-trip survived
-key 0
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-04 — auto-closed by the seven watcher: `test-core#src:test/test_ansiterm_raw_write.pas@1` passes at e2eece6e6f94 (tier native); it was red at 124d83cf494b. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
