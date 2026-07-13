---
prio: 60
---

# bug: FPC could not compile HEAD — cold bootstrap broken (RESOLVED 6e523474)

- **Track:** A (compiler core)
- **Found:** 2026-07-13, from Track T's `fpc-bootstrap` job sitting STILL-RED on borg
- **Resolved:** 6e523474

## What

FPC 3.2.2 refused to compile `compiler/compiler.pas`:

```
parser.inc(2258,39) Error: Identifier not found "ParamIsVarRecArray"
parser.inc(2260,44) Error: Identifier not found "ParamIsOpenArrayScalar"
parser.inc(2264,12) Error: Identifier not found "ByRefArgStartsExpression"
parser.inc(4090,23) Error: Identifier not found "ParseClassRecordSelectors"
compiler.pas(909) Fatal: There were 4 errors compiling module, stopping
```

All four are defined LATER in `parser.inc` than they are first called. pxx pre-scans
declarations and accepts use-before-definition; FPC does not.

## Why it hid

FPC only matters for the COLD bootstrap (it seeds the first binary). Every pxx-built
stage — `make all`, self-host fixedpoint, `make test`, the whole cross matrix — stayed
green, because the self-hosted compiler compiles its own source just fine. Only the
`fpc-bootstrap` job sees it, and that job reports NOTICE/skip on any host without FPC
installed, so it reads as a pass locally. It was RED on borg (which has FPC) and nobody
had opened a ticket for it.

## Fix

Forward declarations at the top of `parser.inc`, beside the existing forward block. No
code moved. They emit nothing: the FPC-seeded binary comes out byte-identical to the
self-hosted one.

## Guard

`tools/testmgr.py --tier full --job 'fpc-bootstrap#src:compiler/compiler.pas'` — but note
it SKIPS (reporting a green verdict) where FPC is absent. To actually check it:

```sh
fpc -O2 -Tlinux -Px86_64 -o/tmp/pxx-fpc compiler/compiler.pas
```

Anything added to `parser.inc` that is called above its definition must get a forward, or
this breaks again and only borg will notice.
