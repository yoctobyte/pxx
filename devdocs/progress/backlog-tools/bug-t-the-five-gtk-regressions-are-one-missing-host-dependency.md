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
summary: "Seven lost its GTK development headers to the 2026-09-05 dist-upgrade (removed 15:20-17:30, reinstalled by hand 17:59:31), so the 09-05 batch of five gtk jobs failed there, auto-filed, and was closed by whoever verified on a host that has them. CORRECTED 2026-09-06: the 'it has happened four times' recurrence argument is FALSE and the other three batches are NOT this condition -- 08-21 ran on plexus and its own log tail shows gtk_init SUCCEEDING; 08-30 and 09-01 both failed deep inside headers that were present, against two different code defects, each root-caused and fixed. The five test NAMES recur because they carry the widest header surface in the suite, not because one condition recurs. The durable fix stands and is strengthened: a job that cannot tell 'the feature is broken' from 'the toolchain is absent' -- and a ticket set that cannot tell four causes apart -- produces closures nobody can audit."
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

## CORRECTED 2026-09-06 — the recurrence argument was wrong, and it inverts

The original section here read: *"18 gtk regression tickets, in batches on four
dates — 3 on 2026-08-21, then 5 each on 08-30, 09-01 and 09-05 — the same five
tests, closed every time. A transient does not recur on a schedule with
identical membership; a standing host condition does. Every previous closure was
as wrong as tonight's."* **Counted independently by frankB and by me, and both
counts were right. The inference from them was not.**

**The four batches have four different measured causes, and only the last is
this ticket's.** Read off the `host` line and the log tail of each batch:

| filed | rows | host | log tail | cause | closed |
| --- | --- | --- | --- | --- | --- |
| 08-21/22 | 3 | **plexus** | `ok: … gtk_init resolved and called successfully!` | the job **passed** on re-run; auto-closed by the plexus watcher at `de2de369ea6a` | correctly |
| 08-30 | 5 | seven | `pascal26:90: undeclared identifier passed as argument 2 of '__pxx_read'`, on crtl's `pxx_env_buf` | `eefa85d70` — a static in a used header keeps its body, so crtl modules flow through the single-pass walk. Root-caused and reverted `2b64dd1e5`, verified by compiling either side | correctly, real code defect |
| 09-01 | 5 | seven | `pascal26:311: call to undeclared function: __builtin_constant_p` | glib reaches for the builtin because `00ab464bf` claims `__GNUC__ 2.7`; reduced to the literal 0 beside `__builtin_expect` | correctly, real code defect |
| 09-05 | 5 | seven | `uses: unit source not found: gtk` / `C include file not found: "gtk/gtk.h"` | **the headers were absent** | this ticket |

**The middle two batches are positive evidence the headers were PRESENT.** You
cannot reach line 90 of a crtl module pulled in behind `gtk.h`, or line 311 of
glib, without having found and parsed `gtk/gtk.h` first. A missing header stops
at line 2. **The failure depth is the discriminator, and it was in the tickets
all along.**

**Seven's own `apt` history closes it independently** (measured on the box, from
`/var/log/apt/history.log` and `/var/log/dist-upgrade/main.log`, not inferred):

```
2026-08-29 16:36:24  libgtk-3-dev installed
2026-08-29 17:09:56  libgtk2.0-dev installed
   ... present throughout the 08-30 and 09-01 batches ...
2026-09-05 15:20-17:30  dist-upgrade REMOVES both
2026-09-05 17:54:19Z  tree tested          <- headers absent
2026-09-05 17:58:16Z  batch auto-filed     <- headers absent
2026-09-05 17:59:31Z  reinstalled by hand
2026-09-05 19:15:54Z  all five pass at 2a4cd0bcf664
```

**So the passes at 19:15 are the reinstall, not the dist-upgrade** — the upgrade
is what BROKE it. Any disposition that reads "the upgrade fixed it" is backwards,
including the one this seat relayed as an unverified hypothesis on 09-05.

### What the recurrence actually means

**The same five names recur because those five tests carry the widest header
surface in the suite** — Pascal `uses` onto a system header, a curated C binding,
crtl modules pulled in behind both, and GCC builtins inside glib. **Anything that
breaks C header import lands on exactly these five.** They are the canary set,
so identical membership is the EXPECTED signature of four unrelated causes, not
evidence of one.

> **A recurring set of ticket NAMES was read as a recurring MECHANISM.** The
> filer names a job; four different defects wear the same eighteen slugs. This is
> the file's *"the name is not the thing"* at the scale of a ticket batch — and it
> is the one scale where the aggregation is produced by our own tooling.

**And the closure risk inverts.** The danger was never "eighteen closed on a
wrong mechanism"; thirteen were closed on the RIGHT one. It is that a fifth pass
tidies all eighteen under the host-dependency story and **erases two verified
root causes** — `2b64dd1e5` and the `__builtin_constant_p` fix — leaving the next
regression in either path with no prior. **Close the 09-05 five on the headers.
Touch nothing older.**

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
