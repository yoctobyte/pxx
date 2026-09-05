---
slug: feature-p-resolve-delphi-dotted-unit-scope-names
title: "Resolve Delphi dotted unit-scope names (`uses System.Classes`) through a per-library alias table"
track: P
prio: 40
type: feature
status: backlog
owner: ""
blocked-by: []
summary: "`uses System.SysUtils, System.Classes;` answers `uses: unit source not found: system.sysutils`. This is the FIRST wall on every Delphi-flavoured corpus target, measured 2026-09-05 on DWScript: with --mimic-fpc, 7 of 8 probed units stop here and nowhere else, and the 8th (dwsStrings) compiles CLEAN. NOT AN FPC-PARITY DEFECT AND THE TICKET SAYS SO ON PURPOSE -- fpc 3.2.2 fails the SAME way (`Can't find unit System.SysUtils used by ns`), and neither `-UaSystem.SysUtils=sysutils` (rejected as an illegal parameter) nor `-FNSystem` helps; this is a Delphi unit-scope feature neither compiler has. So it is not compat, it is a corpus-reach feature, and it is cheap: `System.Classes` and `Classes` name the same unit and the resolution is a prefix strip plus a lookup. THE HOME ALREADY EXISTS AND IS NOT THE CLI: pxxlib.cfg, the per-directory manifest from feature-dynamic-include-paths-config, already supplies define/undef/mode to units under one tree WITHOUT editing the library's source or passing flags at every invocation, which is exactly the shape a vendored Delphi tree needs. A `unitalias` key there is the proposed spelling; a blanket 'strip any dotted prefix' is NOT, because it would silently merge two units a Delphi program deliberately keeps apart. Enables feature-embed-dwscript-rtti and any other Delphi-namespaced target; does not enable dwsRTTIExposer itself, which needs extended RTTI (see that ticket)."
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
