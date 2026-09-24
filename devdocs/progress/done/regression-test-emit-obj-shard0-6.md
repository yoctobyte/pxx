---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_reaches_crtl_on_the_esp_idf_profile.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-emit-obj#shard0/6 at 0a101662f25f in step 1/33, `./compiler/pascal26 --target=xtensa --emit-obj test/c_reaches_crtl_on_the_esp_idf_profile.c /tmp/c_crtl_xt.o --shard 0/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T09:41:29Z
- **Test source:** test/c_reaches_crtl_on_the_esp_idf_profile.c tools/run_c_conformance_esp.sh
- **Failing step:** line 1 of 33 of the job's recipe; it names `test/c_reaches_crtl_on_the_esp_idf_profile.c`.
  ```
  ./compiler/pascal26 --target=xtensa --emit-obj test/c_reaches_crtl_on_the_esp_idf_profile.c /tmp/c_crtl_xt.o --shard 0/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#shard0/6'` at 0a101662f25f2db6213234e9f56b3f16095a71b5

## Range
> **The named sha `0a101662f25f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0a101662f25f`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
too many arguments: pxx takes ONE source and ONE output
  source: test/c_reaches_crtl_on_the_esp_idf_profile.c
  output: /tmp/testmgr-scratch-958888/c_crtl_xt.o
  IGNORED: --shard
  IGNORED: 0/6
  flags go BEFORE the source: pxx [options] <source> [output]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-24 — auto-closed by the borg watcher: `test-emit-obj#shard0/6` no longer exists as a job at 2bf0ce324673 (renamed, removed, or a selector shift), so nothing can report it. It was red at 0a101662f25f; the close records disappearance, not a fix. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
