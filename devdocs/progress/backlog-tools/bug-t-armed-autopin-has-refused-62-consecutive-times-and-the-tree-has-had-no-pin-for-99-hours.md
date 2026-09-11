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
summary: "The owner armed Track T auto-pin on 2026-09-09 (`fc2ce3d02`, \"go ahead and arm it\"). It has fired ZERO times in 62 verdicts since, and the tree's last pin is v407 at 2026-09-06T21:59 — 99 hours. Cadence before that was ~1/day (10 pins, 08-31..09-06). The blocker is a persistent red FLOOR, not a regression: `optdiff#shard0/12` is in 62 of 62 verdicts, and four lib-test rows (lib_synapse.pas, lib_synapse_ssl.pas, lib_synapse_transitive_unit.pas, crtl_reachability.py) in 39 of 62. THOSE FOUR ARE ONE CAUSE -- Track T bisected all four (plus a test-fpjson row) to the SAME range, bad `fca28056d8ec` / last good `0e3ba86d5208`, 4 commits, and the only one touching lib/rtl/sysutils.pas is `0ffe185bb` (six System names moved out of sysutils). Five rows, one fix, not three lanes. The MINIMUM red count across all 62 is 4, so no verdict was ever close. Auto-pin refuses on any red the current pin does not carry and the allowlist holds 2 entries, so the armed policy is STRICTER than the owner's own standing rule (\"we NEED regular pinning, green or not\", 2026-09-06). Not a code defect: the machinery is doing exactly what it was armed to do. The fork is whether it should. AND THERE IS A CIRCULAR DEPENDENCY, confirmed 2026-09-11 after I wrongly denied it: `lib-test#src:tools/crtl_reachability.py` blocks 41 of 62 and its ACTUAL failure is the builtin cliff (`mimic_threading` / `__pxxclone requires --threadsafe`), clearable ONLY by a pin -- and `make pin` is owner-only. So the fleet cannot break the cycle by fixing tests; auto-pin cannot fire until a human pins once. I denied this by grepping pin-shadow.log for the error text; that log records job IDENTIFIERS (a source fingerprint), never failures."
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

# THE SURVIVING NUMBERS, RE-DERIVED UNDER A POSITIVE CONTROL — 2026-09-11

Everything in this ticket came out of `pin-shadow.log`, and the retraction above is
about misreading that exact file. So the numbers that SURVIVED were produced by
the instrument I had just been shown to be misreading, and leaving them unchecked
would be the same error with a better mood. frankZ named the control and it costs
one line: **grep the file for a string you know IS in it.**

```
  positive control   WOULD PIN 123 · would NOT pin 558 · optdiff 214 · self-host clean 123
  negative control   ZZnotarealjob 0
```

Re-derived whole-line, which is also the fix for the 39-vs-41 fragment-counting
error:

| | |
| --- | --- |
| verdicts since arming | **64** (was 62 when first measured) |
| of those, WOULD PIN | **0** |
| `lib-test#src:tools/crtl_reachability.py` blocks | **41** |
| distinct blocking jobs | **13** |

**THE COUNT IS LIVE AND GROWS; THE ZERO DOES NOT.** Two more verdicts arrived
during the hour I spent writing this ticket, so any bare "62" here is correct-when-
measured and stale by the next cycle. **State it as "zero of N, N still growing",
never as a number** — a reader who re-derives 64 against a written 62 has no way to
tell a stale figure from a wrong one, and this ticket has already produced one of
each.

# THE COMPLETE BLOCKER SET — 13 distinct jobs, and the census above named 7

The ranked list above is by frequency and is not the whole population. Every
distinct job blocking at least one of the 62 verdicts:

```
  lib-test#src:test/lib_synapse.pas                 optdiff#shard0/12
  lib-test#src:test/lib_synapse_ssl.pas             optdiff#shard2/12
  lib-test#src:test/lib_synapse_transitive_unit.pas optdiff#shard5/12
  lib-test#src:tools/crtl_reachability.py           optdiff#shard10/12
  test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas
  test-core#src:test/test_generic_nested_inline_specialize.pas
  test-core#src:test/test_libmanifest.pas
  size-canary#src:tools/size_canary.py
  tools-devtest#00
```

# RETRACTED 2026-09-11, SAME DAY: THE PIN-ONLY RED **IS** IN THE FLOOR, AND THERE **IS** A CIRCULAR DEPENDENCY

**The section below is WRONG and is kept because the instrument that produced it
is the point.** frankZ said *"a red that only a pin can clear, sitting in the
floor that is blocking the pin."* That is **correct**. I contradicted it with a
grep for `TPyDeque` / `mimic_queue` / `pinned builds live lib/rtl` over
`pin-shadow.log`, got zero, and wrote the retraction below.

**`pin-shadow.log` records job IDENTIFIERS, never error text.** A job is named for
a SOURCE FINGERPRINT of what changed, not for what fails inside it. So the grep
did not error and did not return a wrong answer — it answered a question about job
names while I read it as a question about failures. The house failure mode, in a
ticket whose own body cites that rule two sections up.

What is actually true, from `seven.json`'s `job_reason` at `a45908bcf68e`:

```
  job:    lib-test#src:tools/crtl_reachability.py      (src: tools/crtl_reachability.py
                                                             tools/gen_crtl_map.py +50)
  fails:  lib-units: FAIL mimic_threading
          pascal26:199: error: __pxxclone (thread creation) requires --threadsafe ...
          in: stable_linux_amd64/default/../../lib/rtl/palthread.pas
  blocks: 41 of the 62 post-arming verdicts
```

`crtl_reachability.py` itself prints **OK** inside that job (frankS). The failing
thing is the builtin cliff — **clearable only by a pin** — and `make pin` is
owner-only. So:

> **A red that only the owner can clear sits in the floor that stops the machine
> pinning.** The fleet cannot break this cycle by fixing tests.

That changes what this ticket is. It is not "auto-pin refuses until someone fixes
some reds"; it is **auto-pin cannot fire at all until a human pins once**, and the
policy fork below is therefore not optional — it is the only exit that does not
require him to run `make pin` by hand.

**And my 39 was wrong too:** whole-line counting gives **41**, not 39. I had
counted fragments of a comma-split list.

**The one thing that survives from below:** the `gate.sh:533` step and this tier
job are two manifestations of ONE defect, not two defects. Conflating them was not
the error; asserting the tier side was absent was.

# SUPERSEDED — the retraction that was itself wrong, kept for the instrument

frankZ read that red as *"a red that only a pin can clear, sitting in the floor
that is blocking the pin"*, which would be a genuine circular deadlock and would
make this an owner emergency rather than a ticket. **It is not in the floor.**
Zero occurrences of `TPyDeque`, `mimic_queue` or `pinned builds live lib/rtl`
across the whole shadow log, and the reason is structural: it is a **`tools/gate.sh`
step** (`gate.sh:533`), not a tier job, and auto-pin qualifies on the TIER.

So there are two separate problems wearing one shape. The gate.sh row blocks every
agent's LOCAL gate and is genuinely only clearable by a pin — an ordinary
inert-until-pinned row, bad but bounded. The tier floor blocks auto-pin. Clearing
either does nothing for the other. Recorded because the deadlock reading is the
one a careful reader arrives at, and it would route this to the owner as urgent
when the actionable half is five rows with one bisected cause.

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

# ALL FOUR lib-test ROWS ARE ONE CAUSE, AND TRACK T ALREADY BISECTED IT

This is the part that changes the work. `TSTATE.md` gives every one of the four
blocking lib-test rows the **same** range:

```
  bad fca28056d8ec, last good 0e3ba86d5208, 4 commit(s) in range
    lib-test#src:test/lib_synapse.pas
    lib-test#src:test/lib_synapse_ssl.pas
    lib-test#src:test/lib_synapse_transitive_unit.pas
    lib-test#src:tools/crtl_reachability.py
    (and test-fpjson#src:tools/install_lib_candidates.sh, same range)
```

So it is **one cause in a four-commit window**, not four reds needing three
lanes, and the header of this ticket listing them as separate owners was reading
a symptom census as a work census — the thing CLAUDE.md warns about two sections
apart. Five rows, one fix.

**The strongest candidate in the window is `0ffe185bb`** — *"feat(B): six System
names FPC keeps in `system` move out of sysutils, and the unit-level scan was a
second hole"* — the only commit in the range that touches `lib/rtl/sysutils.pas`
(106 lines). synapse leans on sysutils, and `crtl_reachability.py` walks the
crtl/rtl surface, which is exactly what moving six names between units would
perturb. The other three commits in range are Track P argument-loop fixes and a
tstate row.

**NOT CONFIRMED, and I could not confirm it from this box:** `external/synapse` is
ABSENT on plexus, so `test/lib_synapse.pas` stops at `uses: unit source not found:
synacode` and this host SKIPS rather than reproducing. It is present on seven,
which is running the watcher — building there would be touching the instrument
mid-measurement, so I did not. Whoever takes this should reproduce on a box with
`external/synapse` fetched (`tools/install_externals.sh`), or on seven while its
tier is idle.

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
