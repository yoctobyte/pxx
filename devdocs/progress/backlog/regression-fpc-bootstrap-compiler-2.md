---
prio: 40
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: fpc-bootstrap#src:compiler/compiler.pas red at a6698ac28e8b (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T19:00:02Z
- **Test source:** compiler/compiler.pas

## Repro
`tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'` at a6698ac28e8b5dd3a62c2fd79b0c1d8b5c4be12a

## Range
> **The named sha `a6698ac28e8b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a6698ac28e8b`, last good `ee62e6dc0582`, 17 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
rparser.inc(2754,10) Error: Function is already declared Public/Forward "RParseAggregateIntoNode(LongInt;LongInt):LongInt;"
compiler.pas(2133) Fatal: There were 1 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode
(tail)
oes not seem to be initialized
elfwriter.inc(3178,34) Warning: Comment level 2 found
elfwriter.inc(3178,44) Warning: Comment level 2 found
elfwriter.inc(3262,13) Warning: Comment level 2 found
elfwriter.inc(3263,13) Warning: Comment level 2 found
elfwriter.inc(3264,29) Warning: Comment level 2 found
elfwriter.inc(3347,33) Warning: Comment level 2 found
elfwriter.inc(3560,56) Warning: Comment level 2 found
elfwriter.inc(3575,30) Warning: Comment level 2 found
elfwriter.inc(3575,40) Warning: Comment level 2 found
elfwriter.inc(3576,14) Warning: Comment level 2 found
elfwriter.inc(3676,32) Warning: Comment level 2 found
elfwriter.inc(3689,65) Warning: Comment level 2 found
rtti_emit.inc(513,46) Warning: Comment level 2 found
rtti_emit.inc(947,27) Warning: Comment level 2 found
rtti_emit.inc(1013,61) Warning: Comment level 2 found
rtti_emit.inc(1061,43) Warning: Comment level 2 found
rtti_emit.inc(1117,32) Warning: Comment level 2 found
asmfront.inc(333,79) Warning: Local variable "dummyTypes" does not seem to be initialized
asmfront.inc(333,67) Warning: Local variable "dummyNames" of a managed type does not seem to be initialized
compiler.pas(1093,30) Warning: Comment level 2 found
compiler.pas(1098,28) Warning: Comment level 2 found
compiler.pas(1105,43) Warning: Comment level 2 found
compiler.pas(1224,9) Warning: Comment level 2 found
compiler.pas(1232,23) Warning: Comment level 2 found
compiler.pas(1380,20) Warning: Comment level 2 found
compiler.pas(1401,22) Warning: Comment level 2 found
compiler.pas(1403,38) Warning: Comment level 2 found
compiler.pas(1462,37) Warning: Comment level 2 found
compiler.pas(1482,10) Warning: Variable "CCmdDefCount" does not seem to be initialized
compiler.pas(1493,10) Warning: Variable "CCmdUndefCount" does not seem to be initialized
compiler.pas(1942,54) Warning: Comment level 2 found
compiler.pas(2133) Fatal: There were 1 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
