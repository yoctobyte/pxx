---
prio: 70
track: A
---

> **Track A from the job NAME `test-i386`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_stackless_gen.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-i386#src:test/test_stackless_gen.pas at cf9b14600039 in step 2/3, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_i386_slg_x64` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T07:41:43Z
- **Test source:** test/test_stackless_gen.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 3 of the job's recipe; it names `test/test_stackless_gen.pas`.
  ```
  ./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_i386_slg_x64
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-i386#src:test/test_stackless_gen.pas'` at cf9b14600039c2f62d7251b0e05330fb74827be9

## Range
> **The named sha `cf9b14600039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cf9b14600039`, last good `e7a805d13a09`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
(tail)
ok: /tmp/testmgr-scratch-2655869/test_i386_slg  [code=180076B  data=5000B  bss=42396B  procs=259]
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
  near: , ' ' ) ; writeln ; >>> end . unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
