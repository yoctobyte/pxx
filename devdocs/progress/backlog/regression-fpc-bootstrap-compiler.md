---
prio: 40
---

# advisory: fpc-bootstrap#src:compiler/compiler.pas red at 96b6bac331d9 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T17:36:20Z
- **Test source:** compiler/compiler.pas

## Repro
`tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'` at 96b6bac331d9d8b9c838d0055a8e3841157314f1

## Range
bad `96b6bac331d9`, last good `3f5aa914cac5`, 27 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
omment level 3 found
zparser.inc(1228,18) Warning: Comment level 2 found
zparser.inc(1277,18) Warning: Comment level 2 found
zparser.inc(1281,56) Warning: Comment level 2 found
zparser.inc(1434,39) Warning: Comment level 2 found
zparser.inc(1493,20) Warning: Comment level 2 found
zparser.inc(1539,50) Warning: Comment level 2 found
zparser.inc(1930,28) Warning: Comment level 2 found
zparser.inc(1931,28) Warning: Comment level 2 found
fparser.inc(240,28) Warning: Comment level 2 found
elfwriter.inc(151,10) Warning: Local variable "neededLibStr" does not seem to be initialized
elfwriter.inc(263,10) Warning: Local variable "neededLibStr" does not seem to be initialized
elfwriter.inc(781,58) Warning: Comment level 2 found
elfwriter.inc(2458,10) Warning: Local variable "neededLibStr" does not seem to be initialized
elfwriter.inc(2789,30) Warning: Local variable "keptLen" does not seem to be initialized
elfwriter.inc(2790,32) Warning: Local variable "keptStart" does not seem to be initialized
elfwriter.inc(2965,30) Warning: Comment level 2 found
elfwriter.inc(2965,40) Warning: Comment level 2 found
elfwriter.inc(2966,14) Warning: Comment level 2 found
elfwriter.inc(3026,32) Warning: Comment level 2 found
elfwriter.inc(3039,65) Warning: Comment level 2 found
cpreproc.inc(1764,15) Warning: Comment level 2 found
asmfront.inc(335,79) Warning: Local variable "dummyTypes" does not seem to be initialized
asmfront.inc(335,67) Warning: Local variable "dummyNames" of a managed type does not seem to be initialized
compiler.pas(412,9) Warning: Comment level 2 found
compiler.pas(420,23) Warning: Comment level 2 found
compiler.pas(485,37) Warning: Comment level 2 found
compiler.pas(502,10) Warning: Variable "CCmdDefCount" does not seem to be initialized
compiler.pas(513,10) Warning: Variable "CCmdUndefCount" does not seem to be initialized
compiler.pas(899) Fatal: There were 4 errors compiling module, stopping
Fatal: Compilation aborted
Error: /usr/bin/ppcx64 returned an error exitcode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
