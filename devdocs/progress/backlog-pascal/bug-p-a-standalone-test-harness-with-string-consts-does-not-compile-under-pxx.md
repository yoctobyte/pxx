---
slug: bug-p-a-standalone-test-harness-with-string-consts-does-not-compile-under-pxx
track: P
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [pascal, const, harness, testing]
blocked-by: []
summary: "test/test_elfdynsym.pas compiles and runs under FPC and is REFUSED by pxx with `undefined variable (SDL64)` on a program-level string const, and then `no overload of ElfSoExportsSymbol matches these arguments — (Integer, ShortString)`, which says the const was typed as Integer rather than not found. NOT isolated: five reductions all compile clean under pxx — string const after a procedure, with a uses clause, with two var blocks, with an {$include} between the const and its use, and with irregular `=` spacing — so the trigger is a combination none of them reproduce. The cost today is that this harness cannot go in tools/standalone_inc_harnesses.sh (which builds with pxx) and is FPC-built from its own Makefile row instead; the wider worry is that a program-level const silently becoming an Integer is a wrong-value shape, not a diagnostic one."
---

# What was measured

`compiler/pascal26 -O2 test/test_elfdynsym.pas <out>` reports:

```
pascal26:117: error: undefined variable (SDL64)
  near: ) then begin LoadFile ( SDL64 >>> , body )
pascal26:119: error: undefined variable (SDL32)
pascal26:122: error: no overload of ElfSoExportsSymbol matches these arguments
  argument types: (Integer, ShortString)
```

The third line is the interesting one. `undefined variable` alone would be a
scoping miss; **`(Integer, ShortString)` says something was resolved and given a
type**, and the type is wrong. `SDL32` is
`SDL32 = '/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0'`.

FPC compiles the same file and all 14 of its rows pass.

# Reductions that do NOT reproduce

Each of these compiles clean under pxx and prints the right string:

1. string const after a procedure declaration
2. …with `uses SysUtils;`
3. …with two `var` blocks, one before and one after
4. …with `{$include}` of a file declaring a function, between const and use
5. …with irregular spacing (`C= '/three'`, `B  = '/two'`)

So the trigger is a combination, and I did not find it. Banked rather than
microfixed: root-cause-over-microfix, and the harness has a working home
meanwhile.

# Why it costs something

`tools/standalone_inc_harnesses.sh` builds every .inc harness **with pxx**, and
exists because a `.inc` gaining a `defs.inc` reference compiles fine in the
compiler and breaks the harness — invisibly. `test/test_elfdynsym.pas` cannot
join it, so `compiler/elfdynsym.inc` is protected by an FPC-built Makefile row
in `test-nilpy` instead. That is a real guard, at a slower cadence, in the wrong
list.

# The shape that would be worse than this ticket

A program-level string const typed as `Integer` is not a diagnostic failure in
general — here it happened to hit an overload set that refused it. Whether any
shape exists where it silently folds to a number instead is **not established**,
and is the question worth answering first. Start there, not at the harness.
