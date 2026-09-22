---
slug: task-t-a-release-grade-full-green-needs-the-corpora-installed-skip-holes-is-forty
track: T
prio: 60
type: task
status: backlog-tools
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: '**`skip_holes == 0` IS ACHIEVED AND MEASURED: 0 skip-holes at `25c21aedc` on plexus / qemu 10.2.1**, `full` tier, 4952 PASS / 1 FAIL / 1 FLAKY / 0 SKIP of 4954, 1589.3s, frozen-tree guard green and aimed. QUOTE IT WITH THE HOST OR NOT AT ALL -- it is NOT "release-grade green", because the archive holds borg''s `c_crtl_wait.c` failing 550 of 551 on qemu 8.2.2 and a host-free sentence gets reconciled against that within a day. THE BLOCKER THAT MADE THIS A TICKET WAS AN UNMEASURED ADJECTIVE AND IT IS GONE: this said "not started because the volume is at 94%" while nobody had sized the fetch. Measured by replicating the tool''s own `fetch_commit` into a scratch dir (depth-1 + sparse, `.git` excluded from the copy, so upstream repo size is irrelevant): **the whole thing is 43 MB** -- fpc-testsuite 20,060 KB, sqlite 10,492, fpc-rtl 5,756, c-testsuite 2,988, synapse 2,092, lua 1,448, fcl-json 1,356, cjson 104. Predicted 44,296 KB before installing, actual delta 44,308 KB, twelve KB out. 0.4% of the 9.9 GB free, so there was never a cliff and never an owner decision; the ~185 MB transient lands in `mktemp -d` on the SEPARATE 94 GB `/tmp` volume by construction. INSTALLED 2026-09-22 (gitignored, nothing entered the repo); disk still 94% with 9.8G free, inodes still 13%. WHAT THE INSTALL BOUGHT, both denominators because quoting one alone is how this ticket already went wrong once: runnable jobs 4910 -> 4954 (**+44**, the honest measure) and total enumerated 4950 -> 4954 (+4, the one that hides the effect). THE RUN IS RED AND THE RED IS A FIRST OBSERVATION, PRE-REGISTERED AS SUCH BEFORE THE VERDICT: `test-pascal-conformance#shard3/6` fails on `terecs4.pp` (%FAIL test compiled), and that shard was `SKIP 0.0s` in the previous run because it needs fpc-testsuite -- so the row had never executed on this box and the previous green is not a control for it. Measured at compiler `06255ab1878c`: a `destructor` in a RECORD under {$mode delphi} compiles clean with no diagnostic AND NEVER FIRES (probe prints scope-in/scope-out, body unreached), so we do not support record destructors, we only fail to reject them. Tagged `gap: accepts-invalid` per `terecs1.pp`''s precedent since the goal doc decides the class -- us accepting what FPC rejects is not a defect, a differing diagnostic is deferred -- and shard 3 then re-runs 69 pass / 0 fail. It is the WORSE sub-shape of that class and the tag says so: siblings leave the mistake visible at the use site, here there is no use site to fail. THE FLAKY QUALIFIES THIS FAMILY''s OWN HEADLINE: `c_crtl_wait.c` flaked on 10.2.1 (failed attempt 1, passed attempt 2) -- the census''s `0 RED / 361` counts REPORTS and a report is green if any of three attempts passes, so per-report 0/361 stands while per-ATTEMPT 10.2.1 is NOT zero. "Clean on 10.2.1" is the wrong phrase and I used it; the accurate one is deterministic-fail on 8.2.2, retry-absorbed on 10.2.1, which fits the same night''s load finding and makes the upgrade a certain-red-to-rare-flake trade rather than a green. ALSO FIXED HERE, because two seats subtracted a pre-run banner from an end-of-run total and invented a cause: the `CORPUS MISSING -- N job(s)` banner is computed before the first job starts and cannot see an in-run corpus skip, so its 40 against the report''s 46 SKIP looked like six skips with another cause and was one cause counted twice (the six were the NATIVE test-c-conformance shards; the banner''s 24 is 4 cross arches x 6 shards). Hardcoding 46 would repair the row and leave the mechanism, so instead the banner now says AT LEAST N with its aperture named, and `corpus_reconciliation` RECOMPUTES at the end where both numbers exist and prints `banner 40 + in-run 6 = 46`; positive control on the real 40/46 case in `tools/testmgr_corpus_reconciliation_devtest.py`, 18 rows, all green. WHAT WOULD RETIRE THIS TICKET: a `full` tier with verdict GREEN and `skip_holes == 0`. Half is met; the green is EXPECTED from a clean-tree re-run now that `terecs4.pp` is tagged, and expected is not claimed. WHAT WOULD RETIRE ITS NUMBERS: `ls library_candidates/` and `df -h`/`df -i`, which move without anyone touching this file.'
---

# A release-grade `full` green needs the corpora installed — `skip_holes` is 40

## What is already settled, so nobody re-derives it

- **`full` is green off borg.** plexus, qemu 10.2.1, 4904 PASS / 0 FAIL /
  0 FLAKY, 1283.7s, `d03add15c`. Earned **under contention** — another clone's
  testmgr shared the box, 2x timeouts, kills retried — which given the same
  night's load measurement makes 0 FLAKY across 4904 jobs a *harder* green than
  an idle one.
- **`native`'s chronic row was an emulator version difference**, not compiler
  work. Closed in
  `done/bug-t-native-s-red-is-one-row-and-full-s-is-ninety-four-so-they-are-different-problems.md`,
  which holds all of it.

## The job

**Install the corpora on whichever host publishes a release candidate, then
re-run `full` and check `skip_holes == 0`.**

```
tools/install_lib_candidates.sh c-testsuite fpc-testsuite fpc-rtl lua sqlite cjson fcl-json
```

**The target filesystem, measured 2026-09-22 rather than assumed — and the
mount question mattered.** `library_candidates/` is a plain subdirectory of the
checkout, so on plexus it lands on whatever carries `/home/neo/frankH`, and
**`/home` is NOT a separate mount here**: `df -h .` and `df -h /` both answer
`/dev/sdc3`. So the root figure is the right denominator, which was not obvious
before checking.

```
/dev/sdc3   156G  138G  9.9G  94% /          <- bytes: the binding resource
/dev/sdc3   10436608 inodes, 1328744 used, 9107864 free, 13%   <- healthy
/dev/sdd2    94G  6.5G   87G   7% /tmp       <- a SEPARATE volume, and roomy
```

Present today: **5.0 MB, all of it `library_candidates/zlib`.**

**THE INODE CHECK IS THE MIRROR OF ITS OWN PRECEDENT HERE, WHICH IS WHY BOTH
NUMBERS BELONG IN THE TICKET.** On 2026-09-07 seven died on **inodes at 9%
bytes used** — a tmpfs — and took the breadth instrument out for ten hours;
`df -h` alone would have called that box healthy during the exact event. On
plexus it is the other way round: inodes are at 13% with 9.1M free and **bytes
are the ceiling at 94%**. Neither figure predicts the other, and running both
is what tells you which one is binding on the host in front of you. Re-measure
both before and after; a `/tmp`-based staging step has 87 GB available and the
target directory does not.

**Note the recursion before it wastes anyone's time:**
`test-fpjson#src:tools/install_lib_candidates.sh` is **itself one of the 40
skipped jobs**, so the tool that closes the hole is inside the hole. That is
not a blocker — the script runs standalone — but a reader who only looks at the
skip list will think it is.

## The trap this ticket exists to disarm

**"The full tier is green" is the phrase that will get quoted without the
banner.** It already nearly was. The tier prints the qualification itself:

```
!! CORPUS MISSING — 40 job(s) will SKIP, not run.
!! A green verdict here does NOT cover them.
```

So when quoting that green, carry `4904/0/0/46` **and** the 40-job hole, in the
same breath. A green with a hole is progress and is not the goal.

## 2026-09-22 — "MULTI-GIGABYTE" WAS AN UNMEASURED ADJECTIVE AND IT WAS DOING THE DECIDING. THE FETCH IS **43 MB**, SO THE DISK OBJECTION DISSOLVES

**frankuser asked the question that killed this ticket's own premise:** nobody
had sized the fetch. The recommendation read *"not started because the volume is
at 94%"* — **a decision built on a number that did not exist.** zlib was 5.0 MB
and the menu had 24 candidates, and from those two facts everyone (me included)
inferred *multi-gigabyte*.

**MEASURED, by replicating the tool's own `fetch_commit` into a scratch dir
rather than installing** — `depth-1` + sparse checkout with `.git` excluded from
the copy, which is why a naive "how big is FPCSource" estimate is wildly wrong:

| candidate | installed | transient (TMPDIR) | files |
| --- | --- | --- | --- |
| `fpc-testsuite` | 20,060 KB | 70,164 KB | 2,656 |
| `sqlite` (amalgamation) | 10,492 KB | 2,764 KB zip | 4 |
| `fpc-rtl` | 5,756 KB | 55,880 KB | 184 |
| `c-testsuite` | 2,988 KB | 3,308 KB | 882 |
| `external/synapse` | 2,092 KB | 3,128 KB | 61 |
| `lua` | 1,448 KB | 374 KB tgz | 75 |
| `fcl-json` (+fcl-fpcunit) | 1,356 KB | 51,480 KB | 73 |
| `cjson` | 104 KB | 676 KB | 3 |
| **total** | **≈43 MB** | **≈185 MB** | **≈3,900** |

**PRE-REGISTERED AND THEN CONFIRMED, which is the part that makes the number
trustworthy:** predicted 44,296 KB before installing; the actual delta was
**44,308 KB** (`library_candidates` 5,048 → 47,256 KB, `external` 0 → 2,100 KB).
Twelve KB out on 43 MB.

**So: 43 MB against 9.9 GB free is 0.4% of what is available. There is no cliff,
and this was never an owner decision.** `df` after: still `9.8G` free, still
94%; inodes `1328832 → 1332951`, still 13%. **The item comes OFF his list** —
what remains is a fetch someone runs, which I have now run.

**AND THE TRANSIENT SIZE LANDS ON THE RIGHT VOLUME BY CONSTRUCTION, WHICH IS
WHY THE PEAK NEVER MATTERED EITHER.** `fetch_commit` does its work in
`mktemp -d`, i.e. `/tmp` — a **separate** 94 GB volume at 7% here — and copies
only the sparse worktree onto the root volume. So the 185 MB peak never touches
the 94% filesystem. **`/tmp` is reaped at 6h by mtime and `noatime` means
reading does not refresh it**, so a *staged* install left sitting there would
evaporate; that is an argument against staging by hand, not against the tool,
which completes the copy inside one invocation.

### The general form, and it is this session's own rule pointed at an adjective

CLAUDE.md already says **the clause to go measure is the QUANTIFIER**. Here it
was an *adjective* — "multi-gigabyte" — and it had been carried, by me, into a
recommendation for the owner, with the honest-looking hedge *"needs network and
disk headroom"* wrapped around it. **The hedge made the unmeasured adjective
read as the checked part**, which is the hedge-the-premise failure in this
file's own list, arriving in a ticket I wrote after quoting that rule twice
tonight.

**The sizes were knowable in minutes without fetching anything** — pinned
commits, sparse paths, and `curl -sIL` for the two tarballs. The cost of not
asking was that an item nearly reached the scarcest resource in this fleet.

## 2026-09-22 — **`skip_holes == 0` ACHIEVED**, and the run is RED on the row the install made visible. The prediction was registered first.

**Measured: `full` tier, plexus, qemu 10.2.1, `25c21aedc`, 1589.3s wall.**

```
4952 PASS   1 FAIL   1 FLAKY   0 SKIP        (of 4954)
testmgr: RED
frozen-tree-guard: tree frozen for the whole run — verdict is attributable
```

**THE NUMBER WITH ITS POPULATION, WHICH IS THE ONLY FORM THIS SHOULD BE QUOTED
IN: 0 skip-holes at `25c21aedc` on plexus / qemu 10.2.1.** Not "release-grade
green". The archive holds borg's `c_crtl_wait.c` failing **550 of 551** on qemu
8.2.2, so a sentence without its host gets reconciled against that within a day
and read as a contradiction. It is the right number for goal 1 and it is a
statement about one toolchain.

### The prediction, registered before the verdict

**Predicted `skip_holes == 0`, derived rather than guessed** — all 46 skips in
the previous run were corpus-caused (36 `conformance`, 10 `corpus`), so
installing every named corpus had to take them to zero. **It did.** The
falsifiers were written down too, and one of them fired exactly as specified:

> *"a new FAIL -> attribute to a RANGE before attributing to the install.
> Newly-runnable jobs have never run on this box, so a red here is a FIRST
> OBSERVATION, not a regression, and the previous run is not a control for it."*

### The red: `terecs4.pp`, and it is a first observation

`test-pascal-conformance#shard3/6` FAILed on `terecs4.pp — %FAIL test compiled
(must be rejected)`. **That shard was `SKIP ... 0.0s` in the previous run** — it
needs `library_candidates/fpc-testsuite`, absent until today. So this row had
never executed on this box and the previous green is not a control for it.

**Measured at compiler `06255ab1878c`**, because the tag has to say what was
checked and not what was assumed: `destructor Destroy;` inside `TFoo = record`
under `{$mode delphi}` compiles **clean, rc=0, no diagnostic** — and a probe
giving that destructor a `WriteLn` body plus a record local in a procedure
prints `scope-in` / `scope-out` with **the body never reached**. So we do not
support record destructors; we only fail to reject them.

**Tagged `gap: accepts-invalid` in `test/pascal-conformance/pxx.skip`, following
`terecs1.pp`'s precedent**, because the goal doc decides the class outright:
*us accepting what FPC rejects is not a defect*, and a differing diagnostic is
deferred. Shard 3 re-runs **69 pass / 0 fail**.

**AND THE TAG RECORDS WHY THIS IS THE WORSE SUB-SHAPE, which is the part worth
keeping:** `tgeneric21.pp` and `terecs1.pp` leave the mistake visible at the use
site or under an opt-in flag. Here there is **no use site to fail** — a
programmer who writes a record destructor expecting cleanup gets silence and no
cleanup, at any flag. Not open work, per the ranking; but if anyone ever ranks
the `accepts-invalid` rows against each other, this one goes above the rows
whose mistake surfaces somewhere.

### The FLAKY is `c_crtl_wait.c`, and it QUALIFIES this ticket's own headline

`test-core#2051` = `test/c_crtl_wait.c`, reason `qemu`: **failed attempt 1,
passed attempt 2.** This is the row this whole ticket is about, and it flaked on
**10.2.1** — the emulator where the census recorded **0 RED / 361**.

**Both statements are true and they are about different units, which is exactly
the distinction this ticket has spent all night on.** The census counts
REPORTS; a report is green if any of three attempts passes. So:

- **per REPORT on 10.2.1: 0 of 361 red.** Unchanged, still correct.
- **per ATTEMPT on 10.2.1: not zero.** Demonstrated once, here, under
  contention.

**So "clean on 10.2.1" is the wrong phrase and I have used it.** The accurate
one is *deterministic-fail on 8.2.2, retry-absorbed on 10.2.1* — which fits the
same night's load finding (1-2% per-attempt across all five target arms at load
~24) better than a pure emulator story does, and it means the upgrade converts a
certain red into a rare flake rather than into a certain green. **That is still
the right trade and it is a smaller prize than "it goes green".**

### Retirement

The stated condition was *"a `full` tier with verdict GREEN and
`skip_holes == 0` on any host"*. **Half of it is met and measured: 0 skip-holes.**
The verdict was RED on one newly-visible row, now tagged, so a re-run from a
clean tree is expected green — **expected, not claimed.** This section is
written before that run so the expectation is on the record.
