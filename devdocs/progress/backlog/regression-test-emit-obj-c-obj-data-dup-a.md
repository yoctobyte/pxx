---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_obj_data_dup_a.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_obj_data_dup_a.c at 1b59d1bbc364 in step 1/52, `./compiler/pascal26 --emit-obj test/c_obj_data_dup_a.c /tmp/cods_dup_a.o` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T04:37:15Z
- **Test source:** test/c_obj_data_dup_a.c test/c_obj_data_dup_b.c +15
- **Failing step:** line 1 of 52 of the job's recipe; it names `test/c_obj_data_dup_a.c`.
  ```
  ./compiler/pascal26 --emit-obj test/c_obj_data_dup_a.c /tmp/cods_dup_a.o
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_obj_data_dup_a.c'` at 1b59d1bbc364eed83812303246711467fd2dd7c5

## Range
> **The named sha `1b59d1bbc364` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1b59d1bbc364`, last good `1e5371209512`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26: error: compiled successfully but wrote no output file: /tmp/testmgr-scratch-4008039/cods_dup_a.o
(tail)
pascal26: error: compiled successfully but wrote no output file: /tmp/testmgr-scratch-4008039/cods_dup_a.o
  the code was generated; the artefact is not on disk or is empty.
  usual cause: a missing or unwritable directory in that path.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
