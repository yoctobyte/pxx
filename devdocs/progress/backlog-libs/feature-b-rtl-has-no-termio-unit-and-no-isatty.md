---
slug: feature-b-rtl-has-no-termio-unit-and-no-isatty
title: "`lib/rtl` has no `termio` unit and no `IsATTY`, and it is the FPC-compiler march's comptty wall"
track: B
prio: 40
type: feature
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [rtl, unix, tty, fpc-corpus]
blocked-by: []
summary: "`grep -rn IsATTY lib/rtl/` is empty. FPC's `comptty.pas:66` calls `termio.IsATTY(t)` inside `LinuxIsATTY`, so the FPC-compiler-source march stops with `undefined variable (IsATTY)`. TWO units report it -- rgobj and aasmbase -- and they are ONE wall: both diagnostics are `comptty.pas:66`, reached through a shared dependency, so this is not two findings and must not be ranked as two. It is the wall those units reached once `TExecuteFlags` was cleared. fpc's signature takes a `var t: Text` and returns an Integer (1 for a tty), which `LinuxIsATTY` compares against 1; the underlying primitive is `isatty(2)` on the text file's handle."
---

# The wall

```
pascal26:66: error: undefined variable (IsATTY)
  in: /home/neo/src/fpc-trunk/compiler/comptty.pas
  near: begin LinuxIsATTY := termio . IsATTY >>> ( t )
```

Reached 2026-09-11 by [[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]
clearing `cfileutl.pas:136 unknown type: TExecuteFlags`.

## It is ONE wall, not two

rgobj and aasmbase both report it and both report `comptty.pas:66`. Same line,
same file, reached through a shared dependency — the exact shape CLAUDE.md
warns produces a shared-cause reading that is an artefact of the diagnostic.
Units-compiling will move by at most one when this clears, not two.

## Shape

`termio` is a unix RTL unit; the march touches exactly one name in it,
`IsATTY(var t: Text): Integer`, returning 1 for a terminal. The primitive is
`isatty(2)` against the handle behind the text file. A whole `termio` is not
obviously warranted — measure what else the corpus asks for before building
more than the one function and the unit that holds it.
