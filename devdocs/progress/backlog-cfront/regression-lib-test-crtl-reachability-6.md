---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 23 of 66, `python3 tools/gen_crtl_map.py --check`, which names `tools/gen_crtl_map.py`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 39 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py at 351c10608aae in step 23/66, `python3 tools/gen_crtl_map.py --check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T06:44:02Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +37
- **Failing step:** line 23 of 66 of the job's recipe; it names `tools/gen_crtl_map.py`.
  ```
  python3 tools/gen_crtl_map.py --check
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at 351c10608aae0a8a86845f08e5d30388b992d8f0

## Range
> **The named sha `351c10608aae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `351c10608aae`, last good `d28b77ce5d88`, **2 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (11 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: OK -- 43 headers, 27 modules, every declared function reachable from its own header
crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
