---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 23 of 88, `python3 tools/gen_crtl_map.py --check`, which names `tools/gen_crtl_map.py`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 50 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py at cdae8cf6580b in step 23/88, `python3 tools/gen_crtl_map.py --check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T11:19:41Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +48
- **Failing step:** line 23 of 88 of the job's recipe; it names `tools/gen_crtl_map.py`.
  ```
  python3 tools/gen_crtl_map.py --check
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at cdae8cf6580bc5dd40f603391a4e98c5d8317c09

## Range
> **The named sha `cdae8cf6580b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cdae8cf6580b`, last good `2d6e7d5c26db`, **2 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (11 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: OK -- 78 headers, 46 modules, every declared function reachable from its own header
crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `lib-test#src:tools/crtl_reachability.py` GREEN at 0da8a0ae4200 (tier full) and did NOT close this: this is a repeat stub (`regression-lib-test-crtl-reachability-8`, not `regression-lib-test-crtl-reachability`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
