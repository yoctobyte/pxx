---
slug: feature-p-resolve-delphi-dotted-unit-scope-names
title: "Resolve Delphi dotted unit-scope names (`uses System.Classes`) through a per-library alias table"
track: P
prio: 40
type: feature
status: done
owner: ""
blocked-by: []
summary: "LANDED 2026-09-05. `unitalias System.Classes=classes` in a pxxlib.cfg makes `uses System.Classes` resolve, scoped to units under that manifest's tree. Delphi's dotted unit-scope spelling was the FIRST and ONLY wall on the DWScript corpus once --mimic-fpc was passed: 7 of 8 probed units stopped at `unit source not found: system.classes` and the 8th compiled clean; with the aliases declared, all eight get past it and the wall moves 50+ lines further in, to `lclintf` -- DWScript's FPC branch wants Lazarus, which is a DIFFERENT and much larger problem recorded on [[feature-embed-dwscript-rtti]]. DELIBERATELY NOT A PREFIX STRIP: an explicit table, because stripping would silently merge two units a Delphi program keeps apart and the symptom would be a wrong unit rather than a diagnostic. Scoped by the MANIFEST THAT DECLARED IT rather than globally, so two vendored libraries can map the same dotted name differently; that needs no unwind because the manifest path is stored beside the row. FILED AND KEPT AS REACH, NOT COMPAT: fpc 3.2.2 fails identically (`Can't find unit System.SysUtils`), and `-UaSystem.SysUtils=sysutils` is an illegal parameter there while `-FNSystem` does not help -- our oracle cannot do this either. Three test rows, and the two NEGATIVE ones are the test: the same `uses Scoped.Alias` from a program OUTSIDE the manifest tree must still fail (scoping), and a dotted name with no row from a file INSIDE it must still fail (table, not strip). INERT WITHOUT A MANIFEST ROW -- PxxUnitAliasCount = 0 exits before any lookup, which is every existing compilation."
---

# Resolve Delphi dotted unit-scope names

- **Type:** feature (corpus reach), Track P — the `uses` resolution is P's, and
  the manifest key would touch `defs.inc`, which is A's territory to edit rather
  than to ask about.
- **Found:** 2026-09-05, attempting `feature-embed-dwscript-rtti`'s target
  rather than triaging it.

## The measurement

DWScript, `--mimic-fpc -Mdelphi`, HEAD `af8b53310` / compiler `450d7de641d8`:

| unit | verdict |
| --- | --- |
| `dwsStrings` | **compiles clean** |
| `dwsXPlatform` `dwsUtils` `dwsErrors` `dwsExprs` `dwsCompiler` `dwsRTTIExposer` | `unit source not found: system.classes` |
| `dwsSymbols` | `unit source not found: system.sysutils` |

One wall, seven units, and the eighth proves the rest of the pipeline is fine.

## Why this is a feature and not a compat bug

`fpc 3.2.2 -Mdelphi` on `uses System.SysUtils, System.Classes;` answers
`Fatal: Can't find unit System.SysUtils used by ns`. Tried and rejected as
workarounds on the oracle itself: `-UaSystem.SysUtils=sysutils` is an *illegal
parameter* in 3.2.2, and `-FNSystem` does not help because FPC's namespaces
require the unit to declare one. So **our oracle cannot do this either**, and
per the goal file that puts it outside compat entirely. It earns its place on
reach: the Delphi half of the real-world Object Pascal corpus spells its `uses`
this way, and today none of it gets past line 3.

## The proposed shape, and the shape to avoid

`pxxlib.cfg` already exists for precisely this problem — a build profile scoped
to one library's directory tree, applied without CLI flags and **without editing
the library's source**, with the scope following the unit being compiled so
sibling libraries never see each other's settings. A `unitalias` key belongs
there:

```
unitalias System.Classes=classes
unitalias System.SysUtils=sysutils
```

**Do not implement it as a blanket "strip any dotted prefix".** Two units a
Delphi program deliberately keeps apart would silently become one, and the
failure would be a wrong unit rather than a diagnostic — the class of defect
this repo is most careful about. An explicit table also documents, per corpus
target, exactly which mappings that target needed.

## Scope note

This unblocks the DWScript *core* and any other Delphi-namespaced tree. It does
**not** unblock `dwsRTTIExposer`, which needs Delphi extended RTTI
(`TRttiContext` and 14 other `TRtti*` classes) that fpc 3.2.2 only partly has and
pxx does not have at all — see [[feature-embed-dwscript-rtti]] for that
measurement.


## LANDED 2026-09-05 (frankH)

`unitalias <Dotted.Name>=<unit>` in a `pxxlib.cfg`. Registration and lookup in
`paslexer.inc` beside the manifest's other directives; the table in `defs.inc`;
one call in `ParseUsesUnit` (`pasparser_proc.inc`) applied where `lo`/`cName`
are computed, **before anything records an identity**, so `System.Classes` and
`Classes` dedupe as ONE compiled unit rather than two — which they are.

**Scoped by the manifest that declared it**, not globally. The row stores the
manifest path alongside it, and is honoured only while resolving a `uses`
written in a unit whose own nearest manifest is that same file. That is the rule
`define`/`undef`/`mode` already follow, and storing the path means the table
needs no save-and-restore around each unit.

**Inert without a row.** `PxxUnitAliasCount = 0` exits before the cached
manifest walk, so every existing compilation takes the same path it did.

### What it moved, measured

DWScript, `--mimic-fpc -Mdelphi`, eight probed units:

| before | after |
| --- | --- |
| 1 clean, 7 stop at `unit source not found: system.classes` / `system.sysutils` | 8 get past it; all 8 now stop at `lclintf`, 50+ lines further in |

`lclintf` is not this ticket's problem and is not a pxx gap: `dwsXPlatform.pas`
takes `{$IFDEF FPC}` → `{$ELSE} , LCLIntf`, so telling DWScript we are FPC sends
it into **Lazarus**, while not telling it sends it into the Delphi RTL
(`System.IOUtils`, `Posix.*`). Recorded on [[feature-embed-dwscript-rtti]].

### The residual, named rather than left implied

`System.Move`, `System.Length`, `System.SetLength`, `System.FillChar` appear 54,
6, 3 and 3 times in DWScript — those are **qualified identifiers**, not unit
names, and this feature does not touch them. Delphi lets a unit-scope name
qualify a routine. Nobody has measured whether pxx accepts that spelling; that
question has no owner yet and is the next thing to probe if the Delphi corpus is
pursued.

### Gate

`gate.sh quick` GREEN 17/17 including the FPC seed canary and the self-host
fixedpoint. `make test-core` was NOT run and is not claimed: the change is inert
without a manifest row, and the three new rows were each verified by direct
invocation with the exact strings the Makefile greps for.
