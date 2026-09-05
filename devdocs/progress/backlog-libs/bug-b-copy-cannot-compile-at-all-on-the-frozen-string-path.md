---
slug: bug-b-copy-cannot-compile-at-all-on-the-frozen-string-path
track: B
type: bug
prio: 45
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "ANY use of Copy refuses under -uPXX_MANAGED_STRING -- the frozen-string path the Makefile calls FROZEN_PXXFLAGS and the bench compiles with -- because lib/rtl/textfile.pas:291 calls PXXIoErrorHook, which only compiler/builtin/builtinheap.pas declares and which the frozen build does not get. `s := Copy('abcdef',1,3)` is enough. Not managed mode: PXX_MANAGED_STRING is ON by default, so -d is the default and -u is the affected half. Pre-existing, identical on pin v404, and invisible because the only source the frozen path is routinely given is test/hello.pas."
---

# `Copy` cannot compile on the frozen-string path

## Repro

```
$ printf "program t; var s: string[16]; begin s := Copy('abcdef',1,3); end.\n" > /tmp/w.pas
$ ./compiler/pascal26 -uPXX_MANAGED_STRING /tmp/w.pas /tmp/w.bin
pascal26:291: error: undefined variable (PXXIoErrorHook)
  in: ./compiler/../lib/rtl/textfile.pas
  near: LastIOResult := 0 ; if PXXIoErrorHook >>> <> nil then
pascal26:291: error: PXXIoErrorHook is not a procedure or function, so it cannot be called
```

`lib/rtl/textfile.pas:291` is `if PXXIoErrorHook <> nil then PXXIoErrorHook();`.
The only declaration in the tree is `compiler/builtin/builtinheap.pas:611`
(`PXXIoErrorHook: TPXXDivZeroProc`, the 4th of the hook family, unguarded), and
`lib/rtl/sysutils.pas:5867` installs it. The frozen build reaches the reference
without reaching the declaration.

## Scope, measured — not "Copy under some conditions"

| source | `-d` (default) | `-u` (frozen) |
| --- | --- | --- |
| `WriteLn('hi')` | ok | **ok** |
| `s := 'ab'; WriteLn(s)` | ok | **ok** |
| `test/hello.pas` | ok | **ok** |
| `s := Copy('abcdef',1,3)` | ok | **FAIL** |
| `WriteLn(Copy('abcdef',1,3))` | ok | **FAIL** |
| `ParamStr(0)[1]` | ok | **FAIL** (a different error — see below) |

Any mention of `Copy` is enough; it does not need a `WriteLn`, a variable, or a
non-literal argument.

**`PXX_MANAGED_STRING` IS ON BY DEFAULT** — verified with an `{$ifdef}` probe:
no flag and `-d` both print `MANAGED`, `-u` prints `FROZEN`. So the broken half
is the one you have to ask for, which is why this has not bitten anyone. It is
still a real half: `Makefile:134` is `FROZEN_PXXFLAGS := -uPXX_MANAGED_STRING`
and the self-compile bench at `Makefile:427`/`433` uses it — on `test/hello.pas`,
the one source above that still works.

**The flag mechanism is not the bug.** Control:
`-uSOMETHING_NOBODY_DEFINES` compiles the same file fine.

**Pre-existing, not a regression.** `stable_linux_amd64/default/stable_pinned`
(pin v404) fails identically, same line, same message.

## A second failure on the same path, probably a different cause

`ParamStr(0)[1]` under `-u` gives:

```
error: compiler error: call to a runtime stub that was never emitted
(code offset 0 is the ELF entry point). A frontend driver is missing its
stub-emission call for the current flags/target.
```

Also identical on the pin. Recorded here rather than split off because both are
"the frozen path is missing something the managed path gets", and whoever opens
one should look at the other before deciding they are two tickets. If they turn
out to have different causes, split then.

## How this was found

Incidentally, while landing the soft-keyword conversion of the sys*/ParamStr
intrinsics (`bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-
user-names`) — the new test compiled under `-d` and refused under `-u`, and the
pin control showed neither was mine.

**Worth one line for the next reader: `-u` UNDEFINES.** I spent two probe rounds
reading `-uPXX_MANAGED_STRING` as "managed mode on" and had a wrong ticket half
drafted about managed strings. `FROZEN_PXXFLAGS := -uPXX_MANAGED_STRING` at
`Makefile:134` is the line that says which way round it is, and the `{$ifdef}`
probe is the two-second way to stop guessing.
