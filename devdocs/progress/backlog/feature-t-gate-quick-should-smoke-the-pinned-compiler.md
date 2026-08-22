---
track: T
prio: 60
type: feature
blocked-by: []
summary: "Add one line to gate.sh quick: compile a trivial `uses SysUtils` program with $(PXX_STABLE). Track B's ground was silently broken for a day because a Track A commit added a symbol to compiler/builtin/** and used it from lib/rtl/** without moving the pin — the pinned binary's embedded builtin lacked the symbol, so every Track B build died. Nothing in the dev loop builds with the PINNED compiler, so nothing noticed."
---

# `gate.sh quick` should smoke the PINNED compiler against `lib/rtl`

- **Type:** feature (a gate gap) — Track T (`tools/gate.sh`)
- **Status:** backlog
- **Opened:** 2026-08-22, from
  [[bug-a-the-pinned-compiler-cannot-build-librtl-sysutils]]

## The gap

The per-fix loop builds and gates with the **freshly self-hosted** compiler.
Track B builds with the **pinned** one. Nothing in the dev loop ever runs the
pinned binary, so a change that makes the tree's `lib/rtl` require a compiler
newer than the pin is invisible to every gate a dev track runs — while breaking
Track B completely.

That is what happened: `PXXVariantErrorHook` was added to
`compiler/builtin/builtinheap.pas` (compiled INTO the binary) and referenced
from `lib/rtl/sysutils.pas` (ordinary source) in one commit, with no pin. Every
`$(PXX_STABLE) -Fulib/rtl <anything>.pas` then failed with `undefined variable
(PXXVariantErrorHook)` — including a three-line hello-world. It surfaced only as
an ADVISORY `demos#00` red.

## Proposed check

```sh
# the pinned binary must still be able to build the tree's RTL
printf 'program s;\n{$mode objfpc}{$H+}\nuses SysUtils;\nbegin WriteLn(IntToStr(42)); end.\n' > $tmp/pinsmoke.pas
$(PXX_STABLE) -Fulib/rtl $tmp/pinsmoke.pas $tmp/pinsmoke && $tmp/pinsmoke
```

Sub-second, no compiler rebuild, and it fails loudly with the real error. It
belongs in `quick` rather than a breadth tier precisely because the failure it
catches is *created by a dev-lane commit and invisible to the dev lane*.

## Design note — what it must NOT become

This is not "run Track B's gate in the dev loop". It is one file, chosen because
`SysUtils` is what every Track B build pulls, and its whole job is to answer a
single question the dev loop cannot otherwise ask: *can the blessed binary still
build the tree's RTL?* Keep it to that; if it grows into a lib-test shard it
will get deleted for costing ten minutes, which is how the dev loop is supposed
to react.

Consider the same one-liner as a `make pin` PRE-condition, so a pin that would
not fix such a break is caught before it takes the lock.

## Gate

Track T's own breadth run green, and the new check verified both ways — passing
at a pinned/RTL pair that agrees, failing with the real error message at
`f3acfdabf`'s tree.
