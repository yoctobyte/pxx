---
prio: 40
track: A
---

> **Track guessed as A from the FAILING STEP** — line 1 of 1, `mkdir -p /tmp/p26_fpc_canary_u && fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU/tmp/p26_fpc_canary_u -FE/tmp/p26_fpc_canary_u -o`, which names `compiler/compiler.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory red: fpc-bootstrap#src:compiler/compiler.pas at d68ed2fe803c in step 1/1, `mkdir -p /tmp/p26_fpc_canary_u && fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU/tmp/p26_fpc_canary_u -FE/tmp/p26_fpc_canary_u -…` (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T13:44:33Z
- **Test source:** compiler/compiler.pas
- **Failing step:** line 1 of 1 of the job's recipe; it names `compiler/compiler.pas`.
  ```
  mkdir -p /tmp/p26_fpc_canary_u && fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU/tmp/p26_fpc_canary_u -FE/tmp/p26_fpc_canary_u -o/tmp/p26_fpc_canary compiler/compiler.pas
  ```

## Repro
`tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'` at d68ed2fe803c0140d9b24d74bd08eef19d276f8b

## Range
> **The named sha `d68ed2fe803c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d68ed2fe803c`, last good `b3f70093e7d8`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
symtab.inc(15987,10) Error: Identifier not found "DerefPtrArrayShape"
compiler.pas(2573) Fatal: There were 1 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode
(tail)
 Warning: Comment level 2 found
elfwriter.inc(5911,25) Warning: Comment level 2 found
elfwriter.inc(5914,15) Warning: Comment level 2 found
elfwriter.inc(5929,56) Warning: Comment level 2 found
elfwriter.inc(5944,30) Warning: Comment level 2 found
elfwriter.inc(5944,40) Warning: Comment level 2 found
elfwriter.inc(5945,14) Warning: Comment level 2 found
elfwriter.inc(6045,32) Warning: Comment level 2 found
elfwriter.inc(6058,65) Warning: Comment level 2 found
elfwriter.inc(6092,15) Warning: Comment level 2 found
elfwriter.inc(6092,19) Warning: Comment level 3 found
rtti_emit.inc(582,46) Warning: Comment level 2 found
rtti_emit.inc(1025,27) Warning: Comment level 2 found
rtti_emit.inc(1091,61) Warning: Comment level 2 found
rtti_emit.inc(1139,43) Warning: Comment level 2 found
rtti_emit.inc(1195,32) Warning: Comment level 2 found
asmfront.inc(333,79) Warning: Local variable "dummyTypes" does not seem to be initialized
asmfront.inc(333,67) Warning: Local variable "dummyNames" of a managed type does not seem to be initialized
compiler.pas(1357,30) Warning: Comment level 2 found
compiler.pas(1362,28) Warning: Comment level 2 found
compiler.pas(1369,43) Warning: Comment level 2 found
compiler.pas(1420,34) Warning: Comment level 2 found
compiler.pas(1422,26) Warning: Comment level 2 found
compiler.pas(1510,9) Warning: Comment level 2 found
compiler.pas(1518,23) Warning: Comment level 2 found
compiler.pas(1693,20) Warning: Comment level 2 found
compiler.pas(1714,22) Warning: Comment level 2 found
compiler.pas(1716,38) Warning: Comment level 2 found
compiler.pas(1775,37) Warning: Comment level 2 found
compiler.pas(1826,10) Warning: Variable "CCmdDefCount" does not seem to be initialized
compiler.pas(1837,10) Warning: Variable "CCmdUndefCount" does not seem to be initialized
compiler.pas(2358,54) Warning: Comment level 2 found
compiler.pas(2573) Fatal: There were 1 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
