---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_threadsafe_object_offset_zero.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **The SLUG names `c_threadsafe_object_offset_zero`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `emit_obj_target_set_check`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_threadsafe_object_offset_zero.c@2 at aef4ee1310f9 in step 32/683, `tools/emit_obj_target_set_check.sh ./compiler/pascal26 /tmp/emit_obj_target_set` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T21:38:26Z
- **Test source:** test/c_threadsafe_object_offset_zero.c test/c_threadsafe_object_offset_zero_main.c +17
- **Failing step:** line 32 of 683 of the job's recipe; it names `tools/emit_obj_target_set_check.sh`.
  ```
  tools/emit_obj_target_set_check.sh ./compiler/pascal26 /tmp/emit_obj_target_set
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_threadsafe_object_offset_zero.c@2'` at aef4ee1310f98a7f23c965da4dd945a6d766bbfa

## Range
> **The named sha `aef4ee1310f9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `aef4ee1310f9`, last good `f88e0ea1f464`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:5: error: wasm32: RTL helper PXXDynArrayRelease not found -- the unit that defines it was not pulled into this build
(tail)
ok: /tmp/testmgr-scratch-1968863/libctsoz.so  [code=124856B  data=2048B  bss=36728B  procs=559  codeseg=124856B]
emit-obj-target-set: FAILED -- the refusal for wasm32 names no supported set:
  pascal26:5: error: wasm32: RTL helper PXXDynArrayRelease not found -- the unit that defines it was not pulled into this build
  near: AddTwo := a + b ; >>> end ; begin 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-25 — the borg watcher saw `test-emit-obj#src:test/c_threadsafe_object_offset_zero.c@2` GREEN at dcb660109dad (tier full) and did NOT close this: the job's class is `corpus`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
