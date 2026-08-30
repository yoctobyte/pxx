---
prio: 40
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: fpc-bootstrap#src:compiler/compiler.pas red at 6a19b5333e07 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T23:56:18Z
- **Test source:** compiler/compiler.pas

## Repro
`tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'` at 6a19b5333e0797c8d5de6aa9cfc6b3a20f4e1f7d

## Range
> **The named sha `6a19b5333e07` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6a19b5333e07`, last good `d347a85d004a`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
cparser.inc(2089,8) Error: Identifier not found "CNodeArrayShape"
compiler.pas(2194) Fatal: There were 1 errors compiling module, stopping
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
compiler.pas(1157,30) Warning: Comment level 2 found
compiler.pas(1162,28) Warning: Comment level 2 found
compiler.pas(1169,43) Warning: Comment level 2 found
compiler.pas(1288,9) Warning: Comment level 2 found
compiler.pas(1296,23) Warning: Comment level 2 found
compiler.pas(1444,20) Warning: Comment level 2 found
compiler.pas(1465,22) Warning: Comment level 2 found
compiler.pas(1467,38) Warning: Comment level 2 found
compiler.pas(1526,37) Warning: Comment level 2 found
compiler.pas(1546,10) Warning: Variable "CCmdDefCount" does not seem to be initialized
compiler.pas(1557,10) Warning: Variable "CCmdUndefCount" does not seem to be initialized
compiler.pas(2003,54) Warning: Comment level 2 found
compiler.pas(2194) Fatal: There were 1 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the plexus watcher: `fpc-bootstrap#src:compiler/compiler.pas` passes at 739594783143 (tier native); it was red at d35f9dbc31b0. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
