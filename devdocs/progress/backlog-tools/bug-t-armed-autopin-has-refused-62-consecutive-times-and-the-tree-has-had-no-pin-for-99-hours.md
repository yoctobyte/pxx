---
slug: bug-t-armed-autopin-has-refused-62-consecutive-times-and-the-tree-has-had-no-pin-for-99-hours
track: T
type: bug
prio: 85
status: backlog
owner: ""
created: 2026-09-11
found-by: frankuser
tags: [pin, track-t, autopin, owner-blocker, workflow]
blocked-by: []
summary: "The owner armed Track T auto-pin on 2026-09-09 (`fc2ce3d02`, \"go ahead and arm it\"). It has fired ZERO times in 62 verdicts since, and the tree's last pin is v407 at 2026-09-06T21:59 — 99 hours. Cadence before that was ~1/day (10 pins, 08-31..09-06). The blocker is a persistent red FLOOR, not a regression: `optdiff#shard0/12` is in 62 of 62 verdicts, and four lib-test rows (lib_synapse.pas, lib_synapse_ssl.pas, lib_synapse_transitive_unit.pas, crtl_reachability.py) in 39 of 62, first seen 2026-08-16 and 2026-08-27/09-01. The MINIMUM red count across all 62 is 4, so no verdict was ever close. Auto-pin refuses on any red the current pin does not carry and the allowlist holds 2 entries, so the armed policy is STRICTER than the owner's own standing rule (\"we NEED regular pinning, green or not\", 2026-09-06). Not a code defect: the machinery is doing exactly what it was armed to do. The fork is whether it should."
---

# Measured 2026-09-11, from `devdocs/progress/tstate/pin-shadow.log` on origin/master

| | |
| --- | --- |
| armed | 2026-09-09, `pin-armed` committed as `fc2ce3d02` |
| verdicts since arming | **62** |
| of those, WOULD PIN / did pin | **0** |
| last WOULD PIN of any kind | 2026-09-07T21:01Z (`285208414d3f`), BEFORE arming |
| last actual pin | v407, `51901941e`, 2026-09-06T21:59 — **99 hours** |
| pins in the 7 days before that | 10 (08-31 .. 09-06), ~1/day |
| minimum red count across the 62 | **4** — no verdict was ever close |

# The red floor, ranked by how many verdicts each blocks

```
  62/62  optdiff#shard0/12                              first seen 2026-09-01
  39/62  lib-test#src:tools/crtl_reachability.py        first seen 2026-08-16
  39/62  lib-test#src:test/lib_synapse_transitive_unit.pas        2026-09-01
  39/62  lib-test#src:test/lib_synapse_ssl.pas                    2026-09-01
  39/62  lib-test#src:test/lib_synapse.pas                        2026-08-27
  23/62  optdiff#shard5/12, shard2/12, shard10/12
   7/62  test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas
```

`optdiff#shard0/12` is the only universal blocker, but clearing it alone changes
nothing — the floor is 4.

# NOT an environmental skip, and I checked because it would have been the cheap answer

`Makefile:33568` has a loud SKIP for absent synapse
(`bug-b-lib-test-unrunnable-in-a-fresh-clone-no-synapse-fetch`), so "a missing
optional library is being counted as a red" was the obvious hypothesis and it is
**wrong**: `external/synapse` is PRESENT in the watcher's own clone
(`/home/seven/trackt-watch/external/synapse`) as well as in `/home/seven/pxx`.
The skip path is not taken and these are real failures. Recorded because a future
reader will have the same idea.

# Why this is not a Track T code defect

`pin_shadow()` -> `pin_now()` is doing exactly what `pin-armed` documents: tier
`full`, no red the current pin does not already carry, a live passing self-host
job, two consecutive qualifying shas, clean detached tree. Every one of those is
sound. **The machinery is correct and the policy is the question.**

# The tension, stated plainly

Two owner rules now point opposite ways, and both are in CLAUDE.md:

- 2026-09-06: *"we NEED regular pinning, green or not"*; *"sometimes we had a
  worker stop because it was waiting for a pin that never happened"*; a red is a
  reason to pin SOONER.
- 2026-09-07: *"let's get back to 'full green expected'"* — a pin RUNS a full tier
  and EXPECTS it green.

CLAUDE.md already says how to break the tie: **"An expectation that cannot be met
ESCALATES to him; it does not become an indefinite hold."** 62 refusals against a
4-red floor whose members are 10 to 26 days old is an expectation that cannot
currently be met. The 19-day gap that the old rule was written to prevent (v354,
08-19, last green) started the same way.

# The fork, in goal terms, because that is the form he can answer

> **When the tests are not all green, do we want the machine to keep the
> compiler's ground current anyway, or to wait until they are?**

He has answered a version of this before ("green or not") and then raised the bar
("full green expected"), and the two answers were given three days apart about
different situations. This is the situation where they collide.

# What does NOT need him

The four lib-test rows and the optdiff shards are ordinary reds with ordinary
owners, and fixing them clears this without any policy change. That is the better
path if anyone is free:

- `lib_synapse*` (3 rows) — Track B
- `crtl_reachability.py` — Track C / B
- `optdiff#shard*` — Track O / T

**Nobody should WAIT on this ticket.** Per CLAUDE.md's own rule, a session must
not hold a seat pending a pin. This is filed so the gap is visible and attributed,
not so anyone stops.

Supersedes the closed `decide-arm-track-t-autopin-the-evidence-gate-cannot-pass-as-written`,
which asked whether to arm. It is armed. This asks whether armed-and-refusing is
what he wanted.
