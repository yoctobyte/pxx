---
prio: 45
---

# bug: `make bootstrap` (FPC cold-start) is red — compiler source drifted out of FPC compatibility

- **Type:** bug — **Track A (compiler core)**
- **Filed by:** the Track T watcher agent
- **Found:** 2026-07-12 by the new FPC-bootstrap canary (`fpc-bootstrap#00`)

## Symptom

The first line of `make bootstrap` — `$(FPC) $(FPCFLAGS) -o<tmp> compiler/compiler.pas`
— fails on stock master with 4 errors:

```
parser.inc(1063,11) Error: function header "ParseGenericTemplateNamed" doesn't match forward : var name changes templateName => templateNameIn
parser.inc(1065,15) Error: Duplicate identifier "templateName"
parser.inc(1072,19) Error: Identifier not found "templateNameIn"
parser.inc(1636,19) Error: Identifier not found "OrdinalNameToTk"
```

## Why it matters

The FPC seed is the **cold-start path**: the only way to rebuild the compiler on
a box with no blessed `pascal26`, and the escape hatch if a self-hosted binary is
ever lost or corrupted. It is load-bearing precisely when everything else has
gone wrong. Nothing day-to-day uses it (every normal build starts from the
self-hosted seed), so it rots silently — pxx's dialect is laxer than FPC in
places, and the source drifts out of FPC-compatibility with no signal.

Individually these are trivial: a forward declaration whose parameter got
renamed, and a routine that moved. That is exactly the point — cheap to fix the
day they land, archaeology a year later.

## Repro

```
tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'
```

Reports NOTICE (advisory — it does not gate anyone's push; see
[[feature-testmgr-fpc-bootstrap-canary]]). Or directly:

```
fpc -O2 -Tlinux -Px86_64 -o/tmp/p26_fpc compiler/compiler.pas
```

## Fix

Make the forward declaration and its implementation agree on the parameter name,
and give `OrdinalNameToTk` a declaration FPC can see at the use site. No
behaviour change intended — this is FPC-acceptance only; the self-hosted build
already accepts the source.

## Gate

`tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'`
green (canary passes), plus A's usual gate: `make test` + self-host fixedpoint
byte-identical. A full `make bootstrap` from FPC is the real prize but the canary
covers the drift that caused this.
