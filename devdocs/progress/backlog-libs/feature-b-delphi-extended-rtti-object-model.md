---
slug: feature-b-delphi-extended-rtti-object-model
title: "Delphi extended RTTI object model (TRttiContext and friends) in lib/rtl/rtti.pas"
track: B
prio: 30
type: feature
status: backlog
owner: ""
blocked-by: []
summary: "FILED 2026-09-06 to give [[feature-embed-dwscript-rtti]] a named blocker instead of a dead end -- that ticket was ranked at 40 for work nobody could start, and 'needs extended RTTI' appeared in no ticket anywhere (checked: only the DWScript ticket and [[feature-p-resolve-delphi-dotted-unit-scope-names]] mention TRttiContext at all). `lib/rtl/rtti.pas` is 294 lines and exports TRttiMethod and TRttiProc; there is no TRttiContext and `TRttiContext.Create` does not parse. Delphi's model is the reflective object graph -- TRttiContext -> TRttiType -> TRttiMethod/TRttiProperty/TRttiField/TRttiParameter -- walked at runtime, which is a DIFFERENT shape from the classic typinfo GetPropInfo/GetStrProp accessors that lib/rtl/typinfo.pas already implements to FPC parity (16 by-name arms landed 2026-09-05, differentially verified byte-for-byte against FPC's own typinfo). NOT FPC PARITY, AND THAT IS THE POINT: fpc 3.2.2 has TRttiContext and TRttiType but NOT TRttiIndexedProperty, so our usual oracle cannot settle the surface and cannot be diffed against -- this is reach into the Delphi half of the corpus, the same category as the unitalias work. SIZE IS UNSCOPED ON PURPOSE: nobody has costed which subset a real consumer needs, and dwsRTTIExposer alone wants 15 distinct TRtti* classes. Whoever takes it should scope from ONE consumer rather than from Delphi's documentation."
---

# Delphi extended RTTI object model

- **Type:** feature (RTL surface + whatever compiler-side emission it needs)
- **Track:** B to start — it becomes **Track A** the moment it needs richer
  emitted metadata than the compiler already writes, which is likely.
- **Status:** backlog — filed 2026-09-06 as the named blocker for
  [[feature-embed-dwscript-rtti]].

## Why it exists as a row

`feature-embed-dwscript-rtti` measured its own premise false and concluded the
exposer "is not reachable and will not be until pxx has Delphi extended RTTI".
That sentence named no ticket, so the dependency was real and invisible: the
ranker saw a prio-40 feature with `blocked-by: []`.

## What is there now

`lib/rtl/rtti.pas`, 294 lines: `TRttiMethod`, `TRttiProc`. No `TRttiContext`.

The classic API is a **different thing that is already done** — `typinfo.pas`
carries the FPC accessor surface at parity. Do not confuse the two; the DWScript
ticket spent a session's work on the classic half before discovering its target
used neither.

## The oracle problem, stated up front

`fpc 3.2.2` cannot compile `dwsRTTIExposer` either — it lacks
`TRttiIndexedProperty`, which that unit needs eight times. So the usual
`tools/fpc_diff_probe.sh` route settles only the part FPC implements. Expect to
specify from Delphi's semantics and a real consumer, and say so in any claim.

## Scope it from a consumer

Not from the documentation. `dwsRTTIExposer.pas` wants 15 distinct `TRtti*`
classes; a smaller consumer would give a smaller and more defensible first cut.
