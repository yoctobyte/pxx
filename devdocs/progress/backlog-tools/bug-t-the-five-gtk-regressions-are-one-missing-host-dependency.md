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

# The 2026-09-05 gtk batch: seven lost its GTK headers to the dist-upgrade

> **SCOPE: the 2026-09-05 FIVE, and nothing older.** Thirteen of the eighteen gtk
> tickets are already closed on their own, different, verified causes — see the
> four-batch table below. A tidy-up pass folding all eighteen under the
> host-dependency story would **erase two root causes** (`ade0ce525` and the
> `__builtin_constant_p` fix) and leave the next regression in either path with
> no prior to find. Close the 09-05 five here. Touch nothing older.

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

## The 09-05 batch is not a code defect, and the proof is a timestamp

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
| 08-30 | 5 | seven | `pascal26:90: undeclared identifier passed as argument 2 of '__pxx_read'`, on crtl's `pxx_env_buf` | `eefa85d70` — a static in a used header keeps its body, so crtl modules flow through the single-pass walk. Root-caused and reverted `ade0ce525`, verified by compiling either side | correctly, real code defect |
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
root causes** — `ade0ce525` and the `__builtin_constant_p` fix — leaving the next
regression in either path with no prior. **Close the 09-05 five on the headers.
Touch nothing older.**

## Disposition — two arms, and only one is ours

1. ~~**Install the GTK3 dev headers on seven.**~~ **DONE, and nothing is
   pending on the owner.** The section above records the reinstall by hand at
   2026-09-05 17:59:31 and the five passing at 19:15:54. Anyone still carrying
   "seven needs sudo for GTK headers" upward should stop — that request is
   closed. What is NOT closed is that a dist-upgrade can remove them again, and
   only arm 2 covers that.
2. **Make the job declare its precondition** — SKIP when the headers are absent,
   or fail with a message naming the missing package, instead of a compile error
   that reads like a defect. **This is the durable half and it is T's.**

Arm 2 is worth building **even if the headers arrive**, because the shape recurs
for every optional system dependency: a job that cannot distinguish *"the feature
is broken"* from *"the toolchain is absent"* will keep producing tickets that
close wrongly. A SKIP says "not measured"; a RED asserts "broken", and only one
of those is true here. Arm 2 is also the only arm that stops round five.

**Arm 2 is already built once in this repo, for a different dependency, and its
comment states the principle.** `tools/wasm32_gap_census.sh:25-30` refuses to
run at all when `wasm-validate` is missing rather than scoring every source
CLEAN:

```sh
if ! command -v wasm-validate >/dev/null 2>&1; then
  echo "wasm32_gap_census: wasm-validate not found (wabt)." >&2
  echo "  The invalid-ENCODING bucket cannot be filled without it, and a census" >&2
  echo "  that quietly drops that bucket reports every such source as CLEAN." >&2
  exit 2
fi
```

> *"a bucket that silently cannot fill is the same animal as the hole it was
> added to close"* — the file's own words, and precisely the gtk case with the
> polarity flipped: there the absence manufactures a false CLEAN, here it
> manufactures a false RED. **Copy the shape, not the exit code** — a census
> aborts, a test job should SKIP and say which package.

**And do not rank arm 2 by the eighteen tickets, because the eighteen are the
CHEAP side of it.** A false RED is loud: it cost four rounds of triage and it
was eventually caught. A false CLEAN costs nothing visible and is never caught
at all. Seven reports that `clang`, `xdotool` and `wabt` have **never** been
installed on that box — no apt entry, ever — so whatever they gate has been
quietly unmeasured for the entire life of the harness, with no ticket, no red
and no census line to notice. (frank-coordinator, 2026-09-05, from seven's own
apt history.) **Most of arm 2's value is on the side that has produced no
tickets**, and a reader who ranks it by the gtk batch will rank it too low.

## The run-level census — the same correction, counted independently

`devdocs/progress/tstate/runs-seven.ndjson`, 1143 runs, 2026-08-29T16:30:49Z →
2026-09-05T19:27:24Z. Job `test-core#src:test/test_c_gtk.pas`:

**RED in 32 runs of 1143 — 2.8%**, and never scattered. Four bursts, all five
gtk jobs entering and leaving together:

| burst | first red | cleared at | span |
| --- | --- | --- | --- |
| 1 | 08-29 16:30 `e417731e9007` | 08-29 17:15 `d93190c4aea5` | ~45 min (left edge is the archive's start, not the burst's) |
| 2 | 08-30 00:34 `bfec13534396` | 08-30 02:04 `0200df7eabcd` | ~90 min, 13 runs |
| 3 | 09-01 23:24 `1236bf31f930` | 09-02 00:31 `cddae9f3e250` | ~67 min, 8 runs |
| 4 | 09-05 17:58 `7867c5481c01` | 09-05 18:13 `2d6bfadd6025` | ~15 min, 3 runs |

Between the bursts the same five jobs pass on every run — hundreds of them.
**This is the quantitative form of the correction above and it was reached from
a different instrument** (the run archive, not the ticket bodies or seven's apt
log), so it corroborates rather than repeats: "fails every run" is off by a
factor of thirty-five, and four bounded windows that each close within the hour
is the signature of four things being fixed, not of one thing standing.

Recorded here because **a red is only ever as informative as the green behind
it**: the next time these five go red, the question "is this the standing gtk
problem?" has a number to answer it with.

## NEGATIVE RESULT: "the onset commits are docs-only" is NOT evidence — I got this wrong

Banked so nobody re-derives it. Working from the census above I checked what
each burst's red-onset commit touched, found `bfec13534396` (docs only),
`1236bf31f930` (tstate only) and `7867c5481c01` (**two lines of `seven.json`**),
and concluded the cause had to lie outside git — five C-header imports cannot
be broken by a docs commit.

**The inference is void and the owner's per-batch causes are right.** The
watcher samples the tip roughly every eight commits, so the delta between a
green run and the next red one is the **commit RANGE**, not the onset commit's
own diff. Measured: 12 commits between burst 2's green and red runs, 5 for
burst 3, and **209** for burst 4 — touching `compiler/`, `test/chdrstatic` and
`lib/crtl/**`, which is exactly where the owner's `eefa85d70` static-body defect
and the glib `__builtin_constant_p` cause live.

**A sha is a position, not a delta**, and `git show --stat <sha>` answers
honestly about the wrong question. It does not error; it prints a real file
list. Same family as this file's *"the name is not the thing"*, and the guard
is to bracket the range with `git diff --name-only <last-green>..<first-red>`
whenever a watcher verdict is the left-hand side.

## What `uses gtk` actually resolves to — measured, and it names the file

Traced on plexus with `strace -e trace=open,openat,newfstatat` over
`./pascal26 test/test_c_gtk.pas`, in a scratch directory holding **only** the
`.pas` file. The resolver misses every Pascal and local-header candidate in
order — source dir, `lib/rtl`, `lib/pcl`, `lib/asmcore`, `compiler/builtin`,
`lib/crtl/include`, `/usr/include/gtk.h` — and then succeeds here:

```
open("/usr/include/gtk.h", O_RDONLY)             = -1 ENOENT
open("/usr/include/gtk-2.0/gtk/gtk.h", O_RDONLY) = 3
```

That is a **hardcoded absolute fallback**, `compiler/pasparser_proc.inc:3428`:

```pascal
ConcatThree('/usr/include/gtk-2.0/gtk/', cName, '.h', path);
```

> **SUPERSEDED THE SAME EVENING, AND THE PACKAGE CHANGED WITH IT.** Traced at
> `0930d5440`. frankC then landed `a409e19b5` — the gtk3 default ruled on 08-31
> and unimplemented for five days — which **deletes** this arm; at HEAD it is
> `/usr/include/gtk-3.0/gtk/` at `pasparser_proc.inc:3439`, and the arch-specific
> `gtk-2.0/include/` root (GTK 2 keeps `gdkconfig.h` there; GTK 3 does not) is
> gone rather than moved. So the four `uses gtk` tests now want **`libgtk-3-dev`,
> not `libgtk2.0-dev`** — the same package as `gtk3_stock`, which collapses the
> two build-time dependency profiles below into one. The trace above is the
> pre-flip tree and is kept because it is what the failure-depth argument was
> measured against; do not read the line number or the package off it.

with the transitive include roots hardcoded beside it at
`compiler/cpreproc.inc:2507-2510` (`/usr/include/gtk-2.0/`, the arch
`gtk-2.0/include/`, glib, pango, cairo, atk, gdk-pixbuf). The build then reads
some 5700 syscalls' worth of system GTK2 headers.

**This is the file the failure-depth argument is about.** `/usr/include/gtk-2.0/
gtk/gtk.h` absent stops you at `uses: unit source not found: gtk`; present, you
get far enough in to reach line 90 of a crtl module or line 311 of glib. The
depth discriminator has a path now.

**Two corrections it forces:**

- The three "compile-only" gtk tests are **not self-contained**. They depend on
  the host's `libgtk2.0-dev` and its glib/pango/cairo/atk/gdk-pixbuf companions.
  (frankZ inferred self-contained from `uses gtk` plus `test/my_gtk.h` having no
  `#include` lines, and flagged the inference themselves.)
- **`test/my_gtk.h` is a red herring twice over.** The resolver looks for
  `gtk.pas`, `gtk.pp`, `gtk.c`, `gtk.h` — never for a `my_*` name; and the
  positive control confirms it, `test_c_gtk.pas` copied to a directory with no
  `my_gtk.h` in it still compiles `ok`.

## Three dependency profiles, not one

Read off the recipes by frankZ, 2026-09-05:

- `test_c_gtk`, `_call`, `_types` — compile only; **GTK2 dev headers**.
- `test_c_gtk_window` — compiles, then `xvfb-run -a` **executes** it
  (`Makefile:14396-14397`): GTK2 headers *and* a GTK runtime *and* a virtual X
  server. Its job group also names `lib/pcl/gtk3_c.h`.
- `test_c_gtk3_stock` — `-Futest/gtk3stock -I/usr/include/gtk-3.0/`
  (`Makefile:14405`): **GTK3** dev headers, a different package.

So arm 2 is skipping on **two** conditions, not one — a build-time header absent
and a runtime library or display absent. A single `HOST_LIBS` list merges them,
and merging similar-looking things is how this batch reached eighteen slugs.

## Dropped: the job-naming hypothesis

frankZ ran `testmgr`'s own splitter over the live Makefile (2015 jobs): each of
the five is its own job and the first and only source of its group. The tickets
name the right tests; the ~11.8% job-map naming gap does not apply here, and the
"fifth scale of one mechanism" line should not be carried further.

## A THIRD polarity, from the gtk3 flip: a test wearing a green that belonged to the host's library version

`test_c_gtk_types` called `gtk_window_new` with **no `gtk_init`**. GTK 2
tolerates that; GTK 3 aborts. So the flip to GTK 3 surfaced it, and frankC fixed
it as a bug rather than working around it.

Worth recording beside the other two, because it is the worst of the three and
the only one that does not look like a host question from inside the ticket:

- a host condition wearing a **red** — the 09-05 batch;
- a host condition wearing a **green** — verifying at HEAD on a box that has the
  headers;
- **a test wearing a green that belonged to the host's library version.**

**That test was green for five days for a reason unrelated to what it asserts**,
so its green was never evidence about `gtk_window_new` at all — GTK 2's
tolerance was the only thing between a real defect in the test and a red. And
the consequence runs forward: **anyone re-adding the gtk-2 fallback later takes
that green back with them and does not know it.** (frankB, 2026-09-05.)

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

## Citation repair 2026-09-05 — the revert row cited a ghost

`progress.sh check` reported the revert row's sha as a DANGLING SHA. It was: not
on origin, and never was. **Recovered by matching the commit SUBJECT**, which is
this repo's prescribed method and works because the subject survives a rebase
while the id does not:

```
eefa85d70  fix(C): a static defined in a used header keeps its body
ade0ce525  revert(C): "a static defined in a used header keeps its body"   <- the revert
f5708eb77  fix(C): a static defined in a used header keeps its body -- scoped by provenance
```

The row meant **the revert**, so it is now **`ade0ce525`**. The dead id is
deliberately **not repeated here** — `git log -p` on this commit has it if anyone
ever needs it, and a ticket body is the one place it can be mistaken for a live
citation again. (`progress.sh check` flagged this very section on its first
draft, for quoting the ghost while explaining that it was one: **a text
instrument cannot tell a citation from a description of one** — the fourth
instance of that class tonight.) The ghost rate here is ~100% by construction: nearly every sync rebases, so a pre-push
`git log -1` reads a doomed id every time. Pass **no sha** to `resolve` and let
`sync.sh` fill in `PENDING-COMMIT`.

Worth noting what this row was doing: it is one of the two root causes the
summary warns a tidy-up pass would **erase**. A dangling citation on a
load-bearing "do not merge these" argument is the worst place for one — the
reader who checks it finds nothing and concludes the cause was imaginary.
