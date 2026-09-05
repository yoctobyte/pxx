---
slug: bug-t-the-five-gtk-regressions-are-one-missing-host-dependency
track: T
type: bug
prio: 55
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "Seven has NO GTK development headers, so five gtk jobs fail there every run, auto-file, and get closed by whoever verifies on a host that has them. It has happened FOUR times: 18 tickets in batches on 08-21, 08-30, 09-01 and 09-05, same five tests, closed every time. The disposition cannot be a fifth closure. The durable fix is the test declaring its precondition — SKIP or a message naming the missing package — because a job that cannot tell 'the feature is broken' from 'the toolchain is absent' generates tickets that close wrongly forever. Installing the headers is owner-only (sudo) and fixes this instance, not the shape."
---

# Five gtk jobs refile every run because seven has no GTK headers

## The cause, read off the log tails

| job | logged error |
| --- | --- |
| `test_c_gtk`, `_call`, `_types`, `_window` | `uses: unit source not found: gtk` |
| `test_c_gtk3_stock` | `C include file not found: "gtk/gtk.h" (searched: /usr/include/gtk-3.0/, …)` |

`gtk` is **not an in-tree unit** — no `gtk.pas` or `gtk.h` exists in the repo, so
`uses gtk` resolves to a *system* header and "unit source not found" means the
host has none. The fifth uses the curated `gtk3_c` binding, fails in different
words and the same cause, and **names the directory it searched**.

Not GTK2, not GTK3, nothing at all.

## It is not a code defect, and the proof is a timestamp

The five were closed once tonight attributed to `4760474da` and its revert.
That is impossible: they were tested at `7867c5481`, authored **17:54:19 UTC**,
and `4760474da` was authored **17:58:50 UTC** — the tree they were tested on
predates the commit by four minutes, and `git merge-base --is-ancestor
4760474da 7867c5481` answers no. The tickets were filed at 17:58:16Z, 34 seconds
before that commit existed. (`test-stackless-gen-3` **was** genuinely that
commit — tested at `f2c6ff3288b4`, which does contain it — and is correctly
closed. One of the six was real.)

## Why four rounds of people have closed these wrongly

**A host with the headers passes whether or not a defect exists.** Verifying at
HEAD on plexus — which has both `/usr/include/gtk-2.0/gtk/gtk.h` and
`/usr/include/gtk-3.0/gtk/gtk.h` — returns GREEN and is a true statement about
plexus and silent about seven. frankB, who found this, did the two things that
normally save you (full job not failing step; HEAD not the filed sha) and
neither could catch it, **because the discriminator was never in the tree**.

That is this repo's own *"nothing observably differs is a claim about ONE
target"* in a variable the rule does not name: not an architecture, **the build
host's installed packages**.

## The recurrence is the argument

**18 gtk regression tickets, in batches on four dates** — 3 on 2026-08-21, then
5 each on 08-30, 09-01 and 09-05 — **the same five tests, closed every time.**
Counted independently by frankB and by me. A transient does not recur on a
schedule with identical membership; a standing host condition does. **Every
previous closure was as wrong as tonight's, and a fifth closure buys another
fortnight.**

## Disposition — two arms, and only one is ours

1. **Install the GTK3 dev headers on seven.** Fixes this instance. `sudo` on a
   machine, so **owner-only**; frank-coordinator is carrying it up.
2. **Make the job declare its precondition** — SKIP when the headers are absent,
   or fail with a message naming the missing package, instead of a compile error
   that reads like a defect. **This is the durable half and it is T's.**

Arm 2 is worth building **even if the headers arrive**, because the shape recurs
for every optional system dependency: a job that cannot distinguish *"the feature
is broken"* from *"the toolchain is absent"* will keep producing tickets that
close wrongly. A SKIP says "not measured"; a RED asserts "broken", and only one
of those is true here. Arm 2 is also the only arm that stops round five.

## A trap in the tickets, worth fixing in the filer

The **Failing step** block quotes a bare command. For `gtk3_stock` the real
recipe is `./$(COMPILER) -Futest/gtk3stock -I/usr/include/gtk-3.0/ test/…`.
Running the quoted command instead hits a **deliberate** `#error` about
`<gtk/gtk.h>` resolving to GTK2, which reads exactly like a shared-cause smoking
gun and is an artefact of the dropped flags. The other four happen to match
their recipes, which is what makes the fifth easy to get wrong. **A repro line
that silently drops flags is an instrument answering a different question.**

## NEGATIVE RESULT: the plexus GTK2/GTK3 condition is not a defect — do not file it

Two sightings looked like a second finding and are not, which is recorded here so
nobody re-derives it: `pcl/extctrls` (frankD) and `examples/life`
(frank-optimize, isolated cleanly — `$(GTK3_INC)` alone clears it) both fail on
plexus with `#error: <gtk/gtk.h> resolved to GTK2`. **Both were built by hand
without the required include root.** The generic demos rule already passes
`$(GTK3_INC)`, so `make demos` builds `life` correctly, and the `#error` is a
deliberate guard preventing a silent header/library ABI mismatch — it is the
guard *working*, and the good outcome.

So there are three host states producing three different error texts that look
like three bugs: **seven** (no headers → `unit source not found`), **plexus
built by hand** (GTK2 only on the search path → deliberate `#error`), **plexus
built by the Makefile** (correct → passes). Only the first is a problem, and
`decide-which-gtk-a-bare-gtk-gtk-h-means` is already in `decided/`.
