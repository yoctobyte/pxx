---
prio: 40
blocked-by: [bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]
---

# DWScript — compile under pxx + RTTI auto-bind (scripting stress test)

- **Type:** feature / investigation (real-world compat target + RTTI driver)
- **Track:** P (Pascal frontend) — rung of [[feature-pascal-corpus-expansion]]
- **Status:** backlog
- **Owner:** — (**Track B** drives the compile + files gaps; the RTTI half is a
  **Track A** typinfo/codegen driver. Built on `$(PXX_STABLE)`, never rebuilt.)
- **Opened:** 2026-06-26
- **Upstream:** `github.com/EricGrange/DWScript` (mirror; canonical on bitbucket
  egrange/dwscript). Object-oriented Object-Pascal scripting engine — full OOP,
  faster, JS codegen. Delphi-leaning; FPC support weaker than Pascal Script.
- **License:** **MPL 1.1**. Free in open/closed/commercial, but must credit
  DWScript in app credits **and** include/link its source; **modifications to
  DWScript's own source files must be published** (file-level copyleft). Fine to
  vendor; the fork-publish obligation matters if we patch its units.
- **Relation:** the brutal cousin of [[feature-embed-pascal-script]] (do that
  first). Sibling of [[feature-synapse-compile-check]]. The RTTI half is the real
  driver for [[feature-metaclass-descendant-enforcement]]-adjacent typinfo work —
  see "the interesting coupling" below.

## The `blocked-by` edge, and why it is on THIS ticket and not a nearer one

*Added 2026-08-28 by frankB.*
[[bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]]
is what stops `GetPropInfo(AnObject, 'Name')` — the instance-taking spelling —
from resolving: the overloads exist in `lib/rtl/typinfo.pas` and are never
selected, so the call binds the `PClassRTTI` arm and segfaults.

The edge sits here because this is the only ranked ticket that actually needs
that spelling. **Checked rather than assumed:** every existing consumer in this
repo — `classes_lite.pas:130,155`, `gtk3widgets.pas:552,561,580,585` — calls
`GetPropInfo(cls, name)` with a class pointer it already holds, so none of them
is blocked and an edge on any of them would be false. `dwsRTTIExposer`'s whole
premise is binding an arbitrary HOST OBJECT handed in from script, which is the
instance spelling by construction, and vendored FPC code will spell it FPC's way.

A false edge would rank correctly for the wrong reason and outlive the reason —
so if the RTTI half of this ticket turns out to reach only the type-level API,
delete this edge rather than leaving it as decoration.

## Why this is the sharper test case

DWScript's headline feature is `dwsRTTIExposer.pas` — **expose any host class to
script automatically via extended RTTI**, no manual registration ("integrate with
anything in the hardcoded library"). That is exactly the feature worth having,
and it only works if **pxx emits walkable extended RTTI**. So this ticket couples
two things:

1. **Compile DWScript under pxx** — a much harder Object Pascal codebase than
   Pascal Script (generics, anonymous methods, advanced RTTI, Delphi-isms). As a
   conformance test it finds far more gaps — deliberately. Expect a stream of
   Track A tickets; that is the point.
2. **Make the RTTI connector actually bind** — needs `lib/rtl/typinfo.pas` + the
   compiler's RTTI emission rich enough that the exposer can enumerate published
   members of a host class and call them. This is the concrete, valuable target
   for the extended-RTTI backend (a real consumer, not a synthetic one).

## Approach

- Sequence **after** Pascal Script lands — reuse the `{$mode delphi}` / mimic-fpc
  groundwork and the gap-filing rhythm.
- Phase 1: compile the DWScript **core** (tokenizer, compiler, exec) only — skip
  the RTTI connector — and run a plain script with no host binding. Gate the long
  tail of language gaps as Track A tickets.
- Phase 2: bring up `dwsRTTIExposer` against pxx RTTI; expose one host class,
  call a method from script. This is where the typinfo/RTTI-emission work gets
  driven and validated.

## Done when

Phase 1: `$(PXX_STABLE)` builds the DWScript core and runs a script. Phase 2: a
host class is reachable from a script purely via the RTTI exposer (no manual
registration), proving pxx's extended RTTI is walkable.

## License compliance (we honour it)

If we ship a demo or test app on DWScript, we **follow MPL 1.1 and give the
attribution** — credit DWScript in the app's credits, include or link its source,
and if we patch any DWScript unit, publish those changes (file-level copyleft).
Fair trade; bake the credit + source link into the demo from the start.

## Risk / note

This is a deep target — likely the single richest source of Track A language +
RTTI tickets we have. Treat it as a long-running driver, not a quick win; park in
`unfinished/` between bursts, keep the gap tickets flowing.
