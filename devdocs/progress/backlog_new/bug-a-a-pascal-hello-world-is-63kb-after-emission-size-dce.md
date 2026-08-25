---
slug: bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce
title: "feature-emission-size-dce is done, and `WriteLn('hello')` still emits 63,760 bytes"
track: A
prio: 30
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Raised out of decide-how-much-string-machinery-the-basic-frontend-gets, decided 2026-08-25. That decision accepted ~100 KB BASIC binaries on the grounds that binary size is a GENERAL problem with a general answer (reachability-gated emission), not a per-frontend one. But feature-emission-size-dce is marked done while a Pascal hello-world is still 63,760 bytes -- so either the pass is not reaching this, or the done ticket's scope was narrower than its title."
---

# The measurement

| program | size |
| --- | --- |
| `10 PRINT "hello"` (.bas, no USES) | 559 B |
| `WriteLn('hello')` (.pas) | **63,760 B** |
| `test_basic_comprehensive.bas` (has USES) | 103,935 B |

The mechanism is known and is not subtle: `DetectPascalRuntimeNeeds` sets
`needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING')`, and
`PasApplyDefaults` defines that symbol **unconditionally** — so every Pascal
program pulls `builtinheap`, always, whether or not it touches a managed string.

# Why this is filed as a bug rather than an optimisation

[[feature-emission-size-dce]] is in `done/` and its stated goal is *"emit only
reachable code ... emit a unit routine only if reached from the program entry"*,
with `hello.pas` named in its own text at ~31.6 KB against a ~29 KB reachable
baseline. The current 63,760 bytes is worse than the number the done ticket was
arguing about. Something regressed, or the pass never covered the
unconditional-`PXX_MANAGED_STRING` door, or the ticket closed on a narrower
slice than its title. `root-cause-over-microfix.md` applies: find out which
before writing anything — the answer changes what the fix is.

# What depends on it

[[decide-how-much-string-machinery-the-basic-frontend-gets]] deferred BASIC's
559-byte unit-free binary to this ticket rather than building a BASIC-only
conditional runtime pull. If this lands, that property comes back on its own,
for every frontend, instead of for one.

# Do not

Fix it by making `PXX_MANAGED_STRING` conditional on a source scan in the Pascal
driver. That is the per-frontend special case the BASIC decision rejected, one
language over. The general mechanism is reachability, and it already has a home.
