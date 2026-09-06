---
slug: feature-embed-dwscript-core
title: "DWScript CORE — compile the 96-unit scripting engine (corpus rung 4)"
track: B
prio: 40
type: feature
status: backlog
owner: ""
blocked-by: []
summary: "Rung 4 of [[feature-pascal-corpus-expansion]], split out of [[feature-embed-dwscript-rtti]] on 2026-09-06 because the two halves have DIFFERENT STARTABILITY: this one is startable today and the exposer is not. THE `lclintf` WALL IS NOT A LAZARUS DEPENDENCY -- measured at 8b55d1918, compiler 5ca36ce7aae9: dropping an EMPTY `lclintf.pas` into Source/ makes the compile walk straight past it, so LCLIntf's own surface is used ZERO times (`grep -o 'LCLIntf\\.'` finds no qualified call either). It is load-bearing only for what it TRANSITIVELY RE-EXPORTS: `dwsXPlatform` imports `System.SyncObjs` in its non-FPC arm only (line 71) while deriving `TdwsCriticalSection` from `TCriticalSection` unconditionally (line 99), so under `--mimic-fpc` the type has to arrive through LCLIntf. A stub re-exporting our own `syncobjs` -- which HAS a real TCriticalSection -- clears it and the wall moves to lines 141/163. WHAT IS ACTUALLY LEFT IS AN ORDINARY RTL GAP LADDER, not a port: `TFileName`, `TLightweightMREW` and `IMultiReadSingleWrite` are absent from lib/rtl (all three checked), and TFileName is a one-line sysutils alias. Prerequisite LANDED: [[feature-p-resolve-delphi-dotted-unit-scope-names]] is in done/, and Source/pxxlib.cfg already carries the 11 unitalias rows. INVOCATION TRAP THAT COST THIS MEASUREMENT AN HOUR: the manifest is found by walking UP from the unit's own directory and the walk STOPS BEFORE THE CWD, so `cd Source && pxx p.pas` silently gets NO manifest while `pxx -FuSource p.pas` from the parent gets one -- same tree, same files, different answer, no diagnostic. Filed as [[bug-p-a-manifest-is-skipped-in-silence-when-the-source-is-compiled-from-its-own-directory]]. Corpus is 96 .pas in Source/ (128 including subdirs), NOT the 102 the parent ticket claimed. Nothing vendored; MPL 1.1 attribution obligations are on the parent ticket."
---

# DWScript core — compile the scripting engine (corpus rung 4)

- **Type:** feature (real-world Pascal corpus target)
- **Track:** B (build on `$(PXX_STABLE)`; language gaps → tickets in the owning lane)
- **Status:** backlog — **split out of [[feature-embed-dwscript-rtti]]** 2026-09-06
- **Upstream:** `github.com/EricGrange/DWScript`, MPL 1.1. Not vendored.
- **Rung 4 of** [[feature-pascal-corpus-expansion]], beside [[feature-embed-pascal-script]].

## Why this is its own ticket

The parent is named for `dwsRTTIExposer`, which needs Delphi extended RTTI and
**cannot be started** — filed as
[[feature-b-delphi-extended-rtti-object-model]]. The core is 94 of the 96 units,
is blocked on nothing but ordinary RTL gaps, and has work available today. One
ticket carrying both ranks the startable half behind the unstartable one, and
the corpus ladder's rung 4 needs something it can actually point a session at.

## The measured wall ladder

At `8b55d1918`, compiler `5ca36ce7aae9`, `--mimic-fpc -Mdelphi -FuSource`,
probe `uses dwsXPlatform` (48 of 96 units name it, so it is the gate):

| stub in Source/ | wall |
| --- | --- |
| none | `unit source not found: lclintf` (dwsxplatform.pas:76) |
| **empty** `lclintf.pas` | `base type not found: TCriticalSection` (:99) — **so LCLIntf's own surface is unused** |
| `lclintf` re-exporting `syncobjs` | `unknown type: TLightweightMREW` (:141), `unknown type: TFileName` (:163) |

**The empty stub is the finding.** It is the probe whose right answer differs
from the default: had LCLIntf been supplying anything, an empty unit would have
produced a list of unknown identifiers naming it. It produced none.

## Next moves, cheapest first

1. **`TFileName`** — `TFileName = string` in `lib/rtl/sysutils.pas`. One line,
   and every Delphi-leaning corpus target wants it.
2. **`IMultiReadSingleWrite` / `TLightweightMREW`** — Delphi 11+ `System.SyncObjs`.
   A real reader-writer lock in `lib/rtl/syncobjs.pas`.
3. Keep stubbing forward from `dwsXPlatform` and record each wall here. **Do not
   commit the `lclintf` stub into DWScript's tree** — it is a probe, and the real
   answer is either an RTL unit of ours or a `unitalias` row.

## Done when

`$(PXX_STABLE)` compiles the DWScript core and runs a plain script with no host
binding. The RTTI exposer is explicitly **out of scope** — that is the parent.
