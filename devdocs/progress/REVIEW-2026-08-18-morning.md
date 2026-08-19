# Morning review — the overnight run of 2026-08-17

**Read time: ~4 minutes.** Written for the stated goal: read decisions, not bug
reports. Updated at each hourly check; the operational detail is in
`devdocs/dev/session-roster.md` and the tickets, not here.

---

## Decisions waiting on you

`tools/progress.sh ready --track U` is the live list. As of the start of the run:

| ticket | prio | what changes on your answer |
| --- | ---: | --- |
| `decide-week-theme-2026-08-17` | 70 | Largely answered by measurement — finish-NilPy and push-the-corpora turned out to be the same week. Probably now a confirmation rather than a fork. |
| `decide-what-an-unwired-test-may-assert` | 55 | Whether ~61 compiling-but-unwired test files may record their own current output as `.expected`. Recommendation: never. See the sharpened version below — the obvious safe answer has a delayed failure mode. |
| `decide-staff-track-c-to-unblock-own-language-first` | 50 | Staffing. |
| `decide-nilpy-exec-injects-a-builtins-key` | 40 | Semantics. |
| `meta-float-accuracy-policy` | 40 | Policy. |

**Also needs a call, not yet a ticket:** Track A had three tickets filed today
with no Track A worker, which is why frank2 was cleared and re-laned mid-evening.
That worked, but it means Track N is now unstaffed and has real queued work.
Whether that is the right steady state is yours.

## Rulings you gave today, now load-bearing

Recorded because they settled work rather than merely answering a question:

- **`--no-shims` is "unsupported"** — we provide no shims, nothing is promised past
  the opt-out, and it is **not to be hardened**. The operative half was *"not
  sneakily load other shims"*, which is what settled where a Python-shaped shim
  lives: `mimic_six.py`, because the tree must say what each shim is. Complicating
  the common path to defend an opt-in audit flag was rejected.
- **Synapse is a test surface, not a dependency** — we have our own TCP stack and
  SSL. Deprioritised the config ticket 45 -> 20 and, more usefully, produced a
  general rule now in `frontend-compat-philosophy.md`: *a corpus is a measuring
  instrument, and difficulty compiling an old one is expected cost, not a bug
  signal.*
- **Float work is low priority** — including formatting, and including a
  performance defect that merely lives in float code. The coordinator broke this
  twice by reclassifying; recorded as: a standing priority ruling is not
  re-litigated by finding another category the ticket also fits.
- **Third-party source never enters the repo** — verified clean (both roots
  gitignored, zero tracked, zero ever added on any branch) and now **enforced**
  rather than documented, by a check in the gate every fix runs.

## What shipped

Compiler (Track A):
- `@procvar` in Delphi mode carries the pointer it holds — root cause of a TLS
  handshake jumping into the stack. Found via an FPC differential; the crash site
  named the wrong subsystem entirely.
- A NilPy module could be compiled and **initialised twice** (two unit rows for one
  file): import-time registration ran twice and two class copies failed `isinstance`
  against each other. Visible output was correct, which is what made it expensive.
- Parent-relative imports (`from ..constants import X`) ignored the dot **level**.
- The shim slot now finds a Python-shaped shim, and three latent bugs in the same
  lookup were fixed with it — one of which was already breaking `.pas` shims from
  any directory other than the repo root.

Libraries (Track B):
- `mimic_six`, the builtin `Warning` hierarchy (all twelve names, read off CPython
  3.12), the dlopen loader **gated for the first time**, `HModule` placed where FPC
  actually keeps it, and a quadratic string build in `strtofloat` (3.1x / 2.2x).

Infrastructure:
- Track T full tier **GREEN: 2695 jobs, zero corpus skips.**
- The synapse corpus is now fetchable, discoverable and **pinned**; it had been
  tracking `origin/master` unpinned, so no two checkouts were guaranteed the same
  source.
- A wiring checker found **98 test files that no build rule ran**. The ten that
  shipped alongside fixes in the last two days are now wired; the rest are triaged.

## A second bug you may want to look at yourself — and it got WORSE on re-measure

`bug-n-a-class-only-module-reads-every-class-attribute-as-zero` (N, p60). Found by
Track B *while measuring whether to build a shim*, and **reproduced independently
here** on a fresh build:

    nodemod.py:  class Node: ELEMENT_NODE = 1; TEXT_NODE = 3; DOCUMENT_NODE = 9
    main.npy:    from nodemod import Node; print(...)

    CPython -> 1 3 9
    pxx     -> 0 0 0

A module whose body is *nothing but a class* reads every class attribute back as
zero. Silent, no diagnostic, correct-looking output.

**Why it matters beyond one shim.** A `mimic_xml_dom.py` would have been ~20 lines,
spec-exact, and complete — `xml.dom.Node` is 12 integer constants and no methods.
It would have compiled, imported cleanly, and made every `nodeType` comparison in
html5lib's treewalkers `0 == 0`, so every node takes the first branch and the walker
emits structurally wrong output with no error anywhere.

That sharpens the rule I gave the worker. I said an overnight *half*-shim looks
present and fails deep inside a caller. The truth is worse: **a complete, spec-exact
shim on a broken substrate does it too.** Completeness is not the protection;
measuring before coding is.

**Re-measured, and the ticket is now `bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero`.**
It is not a class-only-module bug at all — it is **positional and per-class**:

    class K: A = 7      -> K.A = 7   (a statement follows K)
    TOP = 1
    class J: A = 9      -> J.A = 0   (nothing follows J)

Verified here: pxx prints `K.A 7 J.A 0` where CPython prints `7 9`. So it hits **the
last class in any module** — which is an ordinary way to end a file, not an edge
case. Only a statement *after* the class helps; before does nothing. Methods are
unaffected; only attribute initialisers are lost.

The "our existing shims escape by accident because they carry module-level
assignments" conclusion was also wrong. Both are safe, for two *different* reasons,
neither the stated one: `mimic_six` has no classes at all, and `mimic_warnings`'
`catch_warnings` has no class-level attributes. Real exposure today is nil — but the
false guard would have been believed. **The true guard is narrower: a class with
class-level constants must not be last in the file until this lands.**

Worth noting the ticket also records that this is *not* avoidable by writing shims
more carefully. A trailing `_ = None` would mask it, and masking is worse than
hitting it — the shim would then be correct only by virtue of a line nobody could
explain, and would break silently the day someone tidied it away.

## One bug you may want to look at yourself

`bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken`
(N, p60). Found by Track B while writing `mimic_warnings`; **reproduced
independently here** before it went in this digest:

    class W: pass
    def f(c=W): print(c.__name__)
    f()          -> exit 139, segfault, NO diagnostic

The same class passed explicitly prints `W` and exits 0, so the fault is in
materialising the default, not in using a type as a value.

Two things make it worth your attention rather than just the queue. It is
**silent** — every other type-as-a-value gap in this dialect gives a clean refusal
(`the class W cannot be used as a VALUE yet`), and a dialect that refuses
consistently and then dumps core in one corner is worse than one that refuses
everywhere, because the refusals are what teach people to trust the diagnostics.
And `category=SomeClass` is an ordinary Python signature idiom, so this breaks the
upward-compatibility contract on code CPython runs without complaint.

Track B did **not** reshape around it: it used the sanctioned route
(`category=None` + substitute), registered in `track-b-workarounds.md` with a
revert-to note, and the test's warn-with-no-category line is that workaround's own
regression guard. That is the pattern working exactly as designed.

## The finding I'd most want you to read: four subsystems, same defect shape

Filed as `meta-a-second-paths-reimplement-the-first-paths-decisions` (A, p60).
**Four distinct subsystems in one day** where one concept has two mechanisms and
only one carries the capability: `@procvar` lowering, method star-unpack (free
functions get a run-time arity dispatch, methods a compile-time expansion that
refuses defaults), Pascal-vs-`.py` shim attribute resolution, and written-args vs
default-fill. The repo's own rule is two is a smell, three is a design flaw.

Track A's generalisation is the part worth keeping: **wherever a second path
constructs call arguments, it reimplements the first path's decisions and drifts.**
It starts as a copy, the original grows a capability, the copy does not — and
nothing fails at the edit site, because the copy is still internally consistent.

And there is a **grep-able tell**: a hand-rolled compensation sitting next to a
general mechanism. In tonight's segfault, `= None` hand-builds a temp and LEAs it
one branch away from the load that was broken for everything else — somebody hit
this, fixed their case locally, and never saw the general one. When you find a
special case doing manually what a nearby general mechanism does automatically,
the general mechanism is probably broken for everything without its own special
case.

The segfault itself resolved to **one hardcoded `False`**: the written-argument
loop computes by-ref from the parameter; the default-fill path forty lines below
did not, so the callee received the variant's tag (`0xb` = `VT_CLASSREF`) as the
pointer it dereferenced. The type was incidental — a class is simply the only
value that lands in the uncovered path.

## The corpus ladder, corrected — and my error in it

I ranked package/sibling resolution as the top lever and filed Track A work on it.
**The instrument was wrong**: the scan passed only each file's own `-Fu` root, so
cross-package imports recorded as walls. Track B fixed the scan, re-ran it, and
**updated all four citing tickets** — that last part being the half that matters,
since a corrected instrument nobody re-runs just leaves the wrong numbers in
circulation with a fresh timestamp.

Corrected table: `digits` **8**, `CodecInfo` **7**, `xml_dom` 4, inherit-from-itself
3, `six_moves` 3. `webencodings` (6) and `constants` (4) are gone — both artefacts.
**Package/sibling resolution has no row at all.**

The good news is the shape: **15 of the 44 failing files sit behind just two root
causes**, both already filed, both reaching wide through one file each
(`constants.py`, `webencodings/__init__.py`). A table whose top entries are known
single causes is worth much more than one whose top entries are symptoms.

## The theme, if you want one

Nearly every expensive thing today was **a true statement about the wrong subject**,
and the tally is roughly even between the coordinator and the workers:

- `2 skip (corpus absent)` — true in every report for two months, and the cause was
  Track T's own message wrongly claiming the corpora were unfetchable.
- A test asserting `@fpNil <> 0` — true under *two* of three candidate answers, so
  it had been green for the wrong reason.
- A differential built over its own control binary — clean, repeatable, and measuring
  the wrong build.
- `find -name '*.cfg'` returning nothing — taken as "the library config was never
  built", twice, the second time with commit shas attached.
- 6-7 corpus files blocked on `webencodings` — an artefact of the scan passing one
  `-Fu` root, which ranked a non-existent compiler bug as the top lever.

**And the sharpest one, found at the end of the night:** a Track A ticket's
acceptance criterion was *"the emitted binary contains zero `syscall`
instructions — verify with `objdump -d | grep -c syscall`"*. pxx writes ELFs with
program headers only and **no section headers**, and `objdump -d` disassembles
sections — so it prints a three-line header and then `0`, for every pxx binary
ever built. Reproduced here on `compiler/pascal26`: `objdump` says **0**, a
correct instrument says **1093**. That test would have passed on day one and kept
passing whatever the port did.

It is a category worse than the others: those checks could not *discriminate*
between candidate answers; this one **cannot fail at all**. The replacement
(`tools/syscall_scan.py`) fixes the family, not the instance — it reads program
headers, uses per-arch mnemonics (the word "syscall" reports a clean zero on every
cross target regardless of truth), and **refuses to report a count it could not
measure**, because an instrument that cannot distinguish *measured zero* from
*failed to measure* will eventually report the second as the first.

The rule that came out of it, and the one worth keeping: **ask which other
candidate answers would also satisfy the check.** If more than one would, it is not
testing what its name says. Its corollaries — the evidence must sit outside the
thing being varied; a ticket's *cause* ages faster than its *symptom*; a constant
nobody can explain is a wound until proven a baseline — are all the same rule from
different angles.

## A systemic finding: the backlog's SCOPE estimates are stale, not just its causes

Track A audited three Track A tickets tonight and **all three were mis-scoped** —
not marginally, but in ways that would each have cost a session:

1. `feature-port-rtl-over-libc` — acceptance criterion that **could not fail**
   (`objdump -d | grep -c syscall` on a section-header-less ELF). Also: the libc
   import machinery it assumed needed building already works, and the 62
   raw-syscall sites funnel through **one** IR op, so `lib/rtl` needs no edits.
2. `compat-pascal-write-fixed-huge-magnitude` — its newest note restates two
   complaints that the notes *above it* already record as fixed. Measured against
   `decimal.Decimal` at prec=400: digit-for-digit exact. What is live is a
   different thing (`Str` vs `WriteLn`), and bigger than stated —
   `PXXWriteFloatFixed` writes to output and never builds a string, so there is
   **no entry point to route to**.
3. `bug-a-nilpy-leading-double-star` — half already fixed and never closed, and
   the remaining half is not the "~5 lines / one lookahead" the ticket claims:
   free functions got a **run-time** arity dispatch, methods route to a
   **compile-time** expansion that refuses any callee with defaults. Two mechanisms
   for one concept, one of which got the capability. No lookahead fix can work.

**Three for three is a property of the backlog, not three unlucky tickets.** We
already knew a ticket's *cause* section ages faster than its *symptom* section;
this says the same of its *scope*, and scope is what ranking is built on. A ticket
whose stated size is wrong is mis-ranked in both directions — the "quick win" that
is a feature, and the "big job" that is already half done.

Worth deciding whether that changes anything procedurally, or whether "re-measure
before starting" (which is what caught all three) is sufficient.

## Staffing observation, for the steady-state question above

Track B filed **three Track N tickets tonight, two of them on the corpus critical
path, and it found all three by falling over them** while doing Track B work:

- the type-as-default segfault (p60),
- `bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails`
  (p55) — `digits = string.digits` fails because the assignment TARGET breaks
  resolution of the same-named attribute on the RHS; `constants.py:544` is exactly
  that line, and most of html5lib imports `constants.py`,
- the subpackage-directory ticket's `.npy` half, unblocked earlier and still
  waiting.

None was blocked on difficulty; all three were blocked on **nobody holding N**.
That is not structural — Track A can take an N-tagged ticket whose fix lands in
`parser.inc`, and I have queued two that way — but it means N work only happens
when the A worker is free, and tonight the A worker was the bottleneck for the
corpus campaign twice.

Worth noting *how* they were found: a lane doing its own work walked into them.
That is the corpus argument again — the walls are where real code goes, not where
we looked.

## The test-expectation decision got sharper overnight

Worth reading before you answer it, because the *safe-looking* option turns out to
fail the same way as the one we rejected.

The ticket offered: (1) record current output as `.expected`, (2) verify against
the reference implementation first, then record, (3) assert only compile-and-run.
The objection to (1) was that nothing in the file discloses that its expectation
was never checked against anything.

**Track B's addition: (2) checks the oracle ONCE, at wiring time, and then records
the answer — and that answer silently ages.** Nothing re-checks it. If CPython's
behaviour changes, or our reading of it was wrong, the file looks exactly like a
verified test forever after. That is (1)'s failure mode on a delay, and it lands on
the same objection: a once-checked file says nothing either, past the day it was
written.

**The better instance: make the test dual-runnable.** `test/lib_mimic_warnings.npy`
runs unmodified under real CPython and its output is compared. That moves the
oracle from *a step in a procedure* to *a property of the file* — it cannot go
stale, because it is re-checked every time anyone runs it.

It also forces a useful discipline: you must decide what the two implementations
genuinely share. That test asserts **stdout only**, because stderr is a documented
deliberate divergence (CPython prefixes `<file>:<line>:` by walking the call stack;
we cannot). Asserting stderr would have encoded our format as CPython's — which is
option 1 smuggled inside option 2.

**Where it stops, stated honestly:** it needs source that is legal input to the
reference implementation. Natural for NilPy, plausible for C, **unavailable for
Pascal** — FPC-vs-pxx needs two builds of one source, which is
`fpc_diff_probe.sh`'s job rather than a property of a file. So it does not replace
option 2; it is the better instance of it wherever the source is dual-legal, and
Pascal still gets option 2 proper.

One practical caution from the same session, which cost a red gate: **assert the
number of `=ok` lines as well as their content**, or a test that silently stops
emitting half its assertions still passes.

## Two corrections the workers made to ME, both worth your attention

Because they bear on how much unsupervised coordination is safe:

**1. I told a worker to revert a workaround the night its bug was fixed.** It would
have turned `lib-test` red — the fix postdates pin v346, and Track B builds on
`pinned`. The worker **re-measured the repro against `pinned`** (still exit 139)
rather than reasoning from timestamps, and declined. I pinned v347; it then verified
the pin carried the fix before firing. Now recorded as a rule: **"fixed" and
"revertible" are two events separated by a pin**, so a registry row is *armed*, not
*fired*, in that window — and an armed revert is a worker blocked on a pin, which is
mine to clear.

**2. I ranked a corpus lever off a table without asking how the number was
produced**, filed Track A work on it, and dispatched a worker. The instrument was
wrong. Track B offered me the excuse that a bad instrument outranks a bad
measurement — true, and it doesn't cover the part that matters: I'd spent the day
telling everyone to check what their instruments can distinguish. Their words, and
they're right: *a wrong number is recoverable; not asking how a number was produced
is what let it dispatch work.*

Net for the night: my errors were four, all of the same shape as the compiler bugs
we were fixing. Both workers caught the two that would have cost real time. That
arrangement worked — but it worked because there were two of them awake, and it is
the honest input to how much of this should run unattended.

## Our regression detection has a silent degradation mode

Found chasing a false alarm I raised: Track T's full tier appeared to report **pin
v347 RED on three jobs**. Both halves of that sentence were wrong.

**It verified v346, not v347.** The verified sha is a docs commit 85 seconds before
the pin commit; `VERSION` at that sha reads 346. The version label is taken from pin
state *at report time* rather than from the tree that was verified.

**And the job names are positional** — `"%s#%02d" % (target, index)`, an index into
the target's `make -n` recipe. So the same name means different files at different
shas:

| name | at the verified sha | at HEAD |
| --- | --- | --- |
| `lib-test#117` | `lib_tls13_keys.pas` | **`lib_tls.pas`** |
| `test-nilpy#12` | `field_class_identity.npy` | **`uses_tkinter_and_configparser.pas`** |

A `test-nilpy` job added tonight shifted everything after it. Nothing in the record
says which sha to resolve against.

**The consequence is bigger than the false alarm: `new_red` / `fixed` diffing
degrades silently whenever the job list changes**, because two runs' red lists
cannot be compared once positions shift — and seven tests were added tonight. The
one red that *was* attributable, `crtl_exp2`, was attributable only because it also
appears in `open_regressions`, where a stable `src:` selector is stored. `Job.sel`
already exists in testmgr; `pin_verify.red` simply does not use it.

Filed for Track T as
`bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label` (p55).
Both unattributed reds reproduce as **pass** under v346, v347 and HEAD, so the
likely truth is transient timeout in a 186-job parallel run — recorded as unproven
rather than closed as flake.

This is "prefer labelled output over positional" — the rule that came out of a probe
trap two hours earlier — living inside our own reporting format.

## A measurement rule worth keeping

**A ladder row counts transitive victims, not importers.** Three corpus files import
`xml.dom`; a fourth inherits it through `from . import base`. Both numbers are
correct, and only the table answers "how many files does fixing this unblock" — a
source grep would have under-scoped the row.

The companion result: `xml_dom` turned out to be a row *in front of* a wall rather
than a wall. All four files clear it and land immediately on `digits` or `weakref`,
so its net unblock is **zero**. That is a measurement that stopped work rather than
starting it, and it was only visible by writing the shim to scratch and re-running
the ladder.

## Overnight: the one finding worth your time

**Six closed tickets, one concept, and the class is still live.** A red that is
really a blown time budget is indistinguishable in the record from a red that is a
wrong value — and it has now been fixed six separate times, per-job, without the
recurrence stopping.

`tools/testmgr.py` reasons about this well. It stretches a job's budget when a
co-tenant run is live (`PEER_TIME_FACTOR`), retries a co-tenant kill, and states the
principle in its own comment: *"A kill/timeout while a co-tenant run was live is a
statement about the BOX, not the artifact."*

**None of that machinery can reach a `timeout N` written inside a make recipe** —
and there are ten. The inner `timeout` kills the process, the recipe returns nonzero,
`make` exits nonzero, and testmgr sees an ordinary `fail`. So the budget stays rigid
on precisely the loaded box the stretching was designed for, the retry rule never
fires, and the report cannot say TIMEOUT.

That is why the six fixes did not generalise: **all six repaired testmgr's own
timeouts.** The inner ones were never in scope, because from testmgr's side they do
not look like timeouts at all.

The worst instance is `Makefile:363` — a GUI binary under a virtual X server, the
most load-sensitive shape in the suite, on a fixed 120s ceiling, inside a 2700-job
tier. That is tonight's `callbacks.npy` red, and it is the fourth timeout-shaped red
of the evening.

Filed as `bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic`
(T, p55) with three composable fixes, and an explicit note **not** to fix it by
raising the constants — that trades a false RED for a slower suite and still leaves
the two kinds of red indistinguishable, which is the cost the six closed tickets kept
paying.

**Why it is on this page rather than just in the queue:** the individual reds were
each cheap to dismiss, which is exactly how the class survived six fixes. Worth
knowing that a report you rely on has been merging two different failures all along.

### The callbacks red itself

Not closed as a flake — enriched and left open. Measured at HEAD with the job's own
recipe: compiles, runs under Xvfb, exit 0, output byte-identical. The code is
**identical** too — every commit between the accused sha and HEAD is prose. And the
same sha reported GREEN on the native tier and RED on full, which puts the variable
in the environment rather than the revision.

Track T's watcher had auto-filed the stub, so this **enriched it in place** rather
than hand-filing a duplicate. With T's agent down, enrichment — not filing — is the
work that goes missing.

One caution recorded in the ticket for the next reader: that sha carries a **third**
verdict, `GREEN (slow)`, and it is not a re-run. The slow tier is exactly one demoted
uforth shard and never touches `test-nilpy`. I read it as a confirming re-run for
about a minute before checking. A per-sha verdict list invites reading later verdicts
as superseding earlier ones when they cover disjoint job sets.

### Follow-up: the bisect landed, and it corrected me

I wrote above that a bisect on the callbacks red would name a commit and be wrong.
**It converged on `5215148bb` and the answer is right** — the commit that stopped
compiling the three tk tests without running them and added the eighteen Makefile
lines that run them under Xvfb. Those lines are where `timeout 120 xvfb-run` entered
the tree: `Makefile:363`, the same line the harness ticket identifies statically. Two
independent routes, one place.

The commit is not a culprit. It introduced the first *execution* of tests that had
been gated on "it still parses" — a good change — and the execution brought a fixed
ceiling the harness cannot stretch.

My error was pattern-matching this onto `crtl_exp2`, where the range spans commits
that all run the job so the landing is arbitrary. Here the range spans the commit
where the job started doing the expensive thing, so the landing is exact. **A
duration-driven failure does not by itself discredit a bisect.** Passed to plexus-T,
since that distinction may be worth encoding in the report.

### And plexus-T found the sharper half — then stopped cleanly

The dispatch is **withdrawn, not pending**: its user asked to wrap the session for a
clean context before my message arrived, and a stop request outranks a dispatch. It
committed two corrections to work it had already shipped (a too-broad rule in
`track-t.md` that the queued fix would trip) and did not start the ticket. That was
the right order — a live inaccuracy you authored is worth fixing before you go; the
new work is not.

Before stopping it found the thing neither of us had: **fixing the visibility breaks
a guard that only works because of the gap.**

`bisect_step` refuses to bisect any regression whose status is `timeout`. The
callbacks bisect ran, converged, and was *correct* — and it ran **only because the
inner timeout was invisible**. Record it as a timeout and that same exact bisect gets
refused: a correct result suppressed by a guard written for the other shape.

So the two changes must land in one commit, with the discriminator being the
distinction that came out of my own wrong prediction — *did the accused commit
introduce or enlarge the job's work?* Written into the ticket in T's words.

I verified the coupling rather than relaying it: `twatch.py:1506` carries the status
onto the ledger specifically so `bisect_step` can tell duration from behaviour, and
the ledger shows `callbacks: fail` against `crtl_exp2: timeout` — this ticket's
thesis demonstrated live in the record.

**The ticket is unclaimed at p55 with both halves documented.** An unstarted p55 here
is not a dropped ball; it is a better handoff than a rushed start would have been.

### One real regression, caught fast (may already be resolved by the time you read this)

`ce57db4cd` — "lower a statement list iteratively" — went **RED on the native tier**
with three `test-core` Pascal tests: nested class type, set literal element types, set
runtime. Attribution is one commit wide: the sha before it was GREEN on native.

**This is not the timeout noise from earlier tonight**, and the distinction is the
point. Native is the fast tier, so there is no contention story, and three related
tests failing together is a behaviour signal rather than a duration one. It is the
first red of the night that survives its own scrutiny.

Routed immediately to frank2, which owns the commit and was still active, with the
choice of fix-forward vs revert left to it. The commit touches `ir.inc` and
`defs.inc` — shared core.

The irony worth noting: this commit is the **stack-overflow half** of the locals-cap
ticket, and doing that half first was correct. So that ticket's ordering constraint
turns out to run both ways.

I did not wake you for it. A worker was on it within minutes with a one-commit range,
and there was nothing you could have done faster.

## Housekeeping for the morning (not done overnight, deliberately)

`tools/progress.sh check` reports **17 resolved tickets awaiting their landed sha**
(`tools/sync.sh` fills them in) and 3 STATUS-DRIFT lines where a ticket's body says
`working` while its folder says otherwise. Both are bookkeeping. Not run overnight
because `sync.sh` pushes on behalf of other lanes' resolves, and doing that
unsupervised is the kind of helpfulness that is hard to unpick.

## Open at the time of writing

- frank2 (A) → `feature-port-rtl-over-libc` **PARKED in `unfinished/`, and the park
  is clean** — verified independently: zero `compiler/` and zero `lib/` diff, no
  CRITICAL from `progress.sh check`. It stopped at synthesising PLT imports from
  codegen with the self-host fixedpoint riding on it, which is not overnight work.
  It leaves behind a working acceptance instrument, real baselines (pxx hello-world
  57, one libc call 55, `/bin/true` 0), a corrected criterion, and a smaller plan:
  libc calls already work with no compiler change, and all 62 raw-syscall sites
  across 11 RTL units funnel through **one** `IR_SYSCALL` op, so the port needs no
  `lib/rtl` edits at all.
- frank2 then pulling its own next Track A item, excluding the policy ticket.
- frank3 (B) → `mimic_warnings` **landed**; `feature-nilpy-six-and-warnings-shims`
  resolved, both halves. `warnings` has left the first-wall table on all three files
  that import it — same shape as `six`. Now on the `string.digits` gap, the next
  wall on those files.
- Pin at **v346**. Track T's agent is down; its watcher is up and files stubs itself.

---

# Morning close-out (written 2026-08-18 ~07:00, after you woke)

**The overnight run ended with a reboot at ~06:09, not a clean stop.** Every session on
borg died mid-flight. Nothing was lost: the one piece of uncommitted work — the
in-progress fix for the night's red — survived in frank2's tree and has since landed.

## What was decided since you woke

- **Week theme — RULED.** Corpora AND finishing NilPy, as **one theme**, not two. The
  measurement is what settled it: the corpus generating N's remaining work IS
  third-party-libraries-as-targets, so the two are the same activity from opposite ends.
  Resolved to `decided/` and, more importantly, **landed as ranking** — six corpus
  tickets to prio 65, above the p60 queue-drain crowd. Esoteric frontends stay unranked
  in `experimental/`: deferred, not rejected.
  **Consequence to expect: the open-bug count will RISE this week. That is the plan.**
- **Staffing — RULED.** frank2 → Track N (dispatched to `regression-test-nilpy-callbacks`,
  p70, one-commit attribution range). frank3 stays Track B, deliberately idle, held for
  the library bugs the corpora are expected to generate.

## The night's red, and why it matters more than a fixed test

`ce57db4cd` was routed as the regressor. **It was not the cause.** frank2 came up cold,
rebuilt the inherited fix, found the three tests STILL failing, and probed instead of
trusting the note. Two defects, and the handoff comment named only the lesser:

1. a missing `seqCur >= 0` guard — real, kept, **insufficient**;
2. `AN_SET_INCL`/`AN_SET_EXCL` call a **procedure** and never assigned `Result`.

(2) is **latent and predates the commit** — verified independently here with
`git show ce57db4cd^:compiler/ir.inc`, which shows the arm already had no `Result :=`.
While the walk RECURSED, the leftover in the result slot was a live value from the frame
just popped and happened to be a valid IR node index. Going iterative re-rolled the
garbage to `16777218` and the fold built an `IR_BLOCK` over it.

**The generalisable bit, and the reason to read this section:** a revert would have gone
green, cleared eleven reds, and read as a clean success — while re-burying a live
uninitialised-`Result` defect behind plausible stack leftovers. Leaving fix-vs-revert
with the owner rather than mandating the revert is what avoided that. "The restructuring
commit is the cause" is the wrong default when the restructuring touches stack layout,
and checking the PARENT is one command.

## Standing state

Master green on the three tests, self-host fixedpoint converged at `9a40458bb`.
`working/` held only by frank2's new claim. Track T is UP on plexus — it was never down;
the reboot took only this box — and has not yet swept `5b43ad800`, so the eleven cross
and conformance reds still LIST as open. They are expected to clear on its next pass,
and nothing needs doing until they do or do not.

Two open regressions are unrelated and predate all of this: `crtl_exp2.c` (16 in range)
and the callbacks one frank2 is now on (1 in range).

## One thing you may want to look at

`bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two` (T, p45). `check`
has been reporting the same 17 pending sha citations for weeks while `sync.sh` reported
nothing to fill — both correct, anchored on different spellings of the field, so the
count could never go down. Found because frank3 escalated a number that would not move
instead of assuming it was leftovers.

---

# Evening addendum — the board has one dominant lever now

`xml_dom` landed (`ac136d7aa`) after **five** substrate refusals, every one correct.
Verified here by value, not by import: `from xml.dom import Node` reads
`1 3 9 8` and CPython reads `1 3 9 8`.

That verification style is the whole point of the ticket's history — **a test asserting
only that the import resolved would have passed during BOTH compiler bugs while the shim
answered zero.**

## The board, and it is lopsided

| row | files |
| --- | ---: |
| **`yield`** | **14** |
| `six_moves` | 5 |
| `xml_etree_elementtree` | 4 |
| `Mapping` / `list` (builtin subclass) | 3 / 3 |

**`feature-nilpy-yield-outside-a-for-loop` is now the single highest-yield item on the
board by nearly 3x**, and it got there by absorbing everything else that was fixed today —
CodecInfo's eight files, then three treewalkers. Every wall we cleared drained into it.

Two things to know before it is scheduled:

- **It needs the generator METHOD form** (`def __iter__` with `yield`, consumed as
  `for t in filter_instance`). The module-level `for x in gen()` form appears NOWHERE in
  these corpora and would move ZERO files. If a report says "yield landed", ask which
  shape.
- **Its step 4 may want the pending boxed-def decision.** Steps 1-3 are independent.

## Compile count: still 6/48

Today moved a great deal and the compile number did not. That is the expected shape and it
is recorded so nobody reads it as failure: the corpus is a chain of walls, and clearing
one moves files ONTO the next. Every worker reported past-vs-onto separately, unprompted,
which is why this is legible at all.

## Still with you

`decide-how-a-compiled-def-carries-its-signature-when-boxed` (U, p88). Gates the
procedural-value bug, the def-rebinding bug, and yield's step 4. Not urgent — both workers
have landable work — but it is now upstream of the board's biggest row.

## Late update — yield is now 18 files, over 4x the next row

`six_moves` cleared (5 -> 0) when the `urllib_parse` shim landed; four of those five files
went straight onto `yield`. Compile count still **6/48**.

| row | files |
| --- | ---: |
| **`yield`** | **18** |
| next largest | 4 |

Every wall cleared today has drained into the same one. Combined with the re-estimate —
**the generator engine is already built and proven for Pascal, so this is frontend
wiring** — yield is now both the largest lever on the board and a smaller job than its
ticket has been claiming. It is the obvious next piece of work and it is queued.

Two new N bugs found by WRITING the shim rather than reading, both verified here against
CPython:

- `bug-n-subscripting-a-container-literal-inside-a-function-segfaults` (p65) —
  `return (1, 2)[0]` inside a function **core-dumps**; at module level it is fine, and
  binding to a local first is fine. Tuple and list both.
- `bug-n-two-argument-super-does-not-parse` (p60) — `super(Filter, self).__init__(...)`
  is `unexpected token`; the zero-arg form works. html5lib writes the two-arg form in
  EVERY filter.

## One item to SCHEDULE rather than queue: yield

`feature-nilpy-yield-outside-a-for-loop` is now **demonstrably the single wall in front of
the entire html5lib filter pipeline.** Tonight `sanitizer.py` and `lint.py` both cleared
two-argument `super` and landed on it. **Zero files compile completely**, and the ladder
count will not move until yield lands.

It was attempted once today and parked with the diagnosis banked — correctly. Three
things make it a scheduling decision rather than a queue pick:

- **It is not blocked on your boxed-def ruling.** Measured: the engine refuses generator
  METHODS outright (`parser.inc:31543`), so the boxed-callable route was never available,
  and the route that works — a lifted free function consumed by a plain for-in — needs no
  callable value. Verified on the html5lib nested-filter shape (`10 20 40 50`).
- **It is smaller than its ticket says.** The generator engine is built and proven for
  Pascal: yield keyword, `AN_YIELD`/`IR_YIELD`, both runtimes, and the
  `GetEnumerator`/`MoveNext`/`Current` object protocol. NilPy has none of it wired.
- **Its remaining failure mode is SILENT STACK CORRUPTION, not a compile error.**
  `PyEmitParamSpills` spills argument registers into every param slot, but in the
  stackless step ABI only `__genself` arrives in a register. The crash is localised, the
  next move is named in the ticket, and the guard-it A/B is recorded.

That last point is why I declined the worker's offer to retry it at the tail of a long
session, and why it should get a session with room rather than the last hour of one. The
more the board depends on it, the more expensive a plausible-but-wrong fix becomes — and
silent corruption is the failure mode that survives a green gate.

**Everything else in N is ordinary queue work.** This one is worth you deciding when.

## Tomorrow's agenda — the decision queue (assembled 2026-08-18 evening)

The user is available for decision tickets tomorrow and asked for the queue to be ready
rather than discovered on the spot. **Eight open `decide-*` tickets, all Track U, all in
`backlog/`**, ranked:

| prio | ticket | note |
| --- | --- | --- |
| 88 | `decide-how-a-compiled-def-carries-its-signature-when-boxed` | the one already in front of them; gates real work, and option B must not be started speculatively |
| 55 | `decide-what-an-unwired-test-may-assert` | |
| 50 | `decide-staff-track-c-to-unblock-own-language-first` | a **staffing** fork — the coordinator must not settle it |
| 50 | `decide-finalize-noop-vs-refusal` | |
| 45 | `decide-unary-minus-widening-in-the-default-dialect` | dialect philosophy; pairs with the FPC-faithful-by-default rule |
| 40 | `decide-one-answer-to-have-i-already-compiled-this-unit` | |
| 40 | `decide-nilpy-exec-injects-a-builtins-key` | |
| 20 | `decide-what-synapse-actually-needs-vs-mimic-fpc` | |

**Why this list is worth ranking rather than just listing:** a resolved decision propagates
priority down its dependency edges, so answering the top one unblocks the chain behind it.
And a `decide-*` that is resolved but never **re-filed into its owning lane** goes invisible
to `ready`/`next` — the work then gets rediscovered later, sometimes with a fix the decision
already rejected. So each answer tomorrow should end with the re-file, not with the answer.

**Also requested for tomorrow: the philosophy conversation we did not get to** — the user
raised it explicitly and it is not a ticket. Flagging it here so it is not lost between
sessions; it belongs alongside `ir-as-substrate.md` and `normalise-dont-special-case.md`
rather than in the queue.

### Agenda UPDATE (evening) — one new decision, and it jumped the queue

**`decide-xml-etree-thin-tree-model-or-a-real-xml-library` (U, p62)** — filed by Track B
after measuring the surface first, so it is decidable in **one read**. html5lib uses
ElementTree as a **tree model, not an XML library**: 3 factories (`Element`, `Comment`,
`ElementTree`) and 10 element members — no `parse`, no `fromstring`, no XPath, no
serialiser (html5lib writes its own `tostring` at `treebuilders/etree.py:262`). One quirk
must be exact: `Comment("x").tag` **is** the `Comment` function, and html5lib compares node
tags against it.

**The fork is not effort — it is whether a module named `xml.etree.ElementTree` may ship
without being able to read XML.** Track B's recommendation is in the ticket: yes, thin,
with the parser surface absent and loud, same call as `mimic_urllib_request`. ~60 lines
plus a differential, ready to start within the hour of an answer.

**Why it outranks its number:** it is 4 of the 8 remaining module-blocked files, it is the
whole of Track B's corpus lever, and a worker is idle behind it with capacity.

### The campaign's standing assumption INVERTED tonight

The missing-module batch **had already shipped** — a re-measure at pinned v352 found 12
`mimic_*` units on disk and gated by `lib-test`. What remains is **8 files, 4 behind the
decision above**, while the **language** walls are **32**, of which **`yield` alone is
18 — more than every missing-module row combined**. So *"Track N is no longer the
bottleneck for this ladder"* was true when written and is now **superseded**: Track N is
the bottleneck again, and Track B's corpus lever is one Track U decision wide.
`feature-nilpy-yield-outside-a-for-loop` reranked 58 → **75** accordingly, with a banner
saying it still must go to a **fresh** session rather than to whoever `next` hands it to.

### A third lighthouse arrived tonight — MINIX (user, 2026-08-18)

Filed as [[goal-compile-minix]], with one decision in front of it:
**`decide-which-minix-is-the-target` (U, p58)** — MINIX 2 / early 3.1.x versus
MINIX 3.2+ (which imported the NetBSD userland and build system). Recommendation in
the ticket is Option A, on the grounds that Option B trades away the bounded scope
that is the entire reason to prefer MINIX over the Linux dot — and if the NetBSD
userland is the prize, it is its own corpus ticket rather than something that must
arrive attached to an OS boot goal.

**Why the goal is worth the slot:** the Linux lighthouse's own analysis names the GNU
inline-asm constraint engine as THE wall (weeks, one subsystem, currently zero
support). MINIX was built for ACK and keeps assembly in **separate `.s` files**, so
`CC=pxx` plus GNU `as` sidesteps it. Add a microkernel's natural ladder, a working
i386 backend, and `--emit-obj` already gated by `make test-emit-obj`, and it is the
rung below the kernel rather than a detour from it.


---

# OVERNIGHT 2026-08-18 → 19 — what landed while you slept

Both workers were cleared around 20:00 and run overnight. Track T confirms green through
`185575980d53` (native, slow, opt, and bench back to 30 rows).

## The bump: `yield` is gone as a wall

**`feature-nilpy-yield-outside-a-for-loop` is DONE** — four commits: generators consumed
by `for`-in, then **generator METHODS** ("the shape the html5lib filters are made of"),
a parameter-count fix, and a Pascal `var` fix. It then cleared the **full cross-target
matrix**, not just `quick`.

Then `feature-nilpy-a-generator-as-a-first-class-value` **also** landed (`g = gen()`,
`list(gen())`, `next(g)`, `__iter__`), plus a fix for **a generator `for`-in inside a
block swallowing the statement after it** — silent, and the kind normally blamed on
anything but the loop.

**Scored honestly by the worker, and this is the number to trust over any headline:**
`yield` is no longer any file's wall, but the html5lib count did not move at the time —
its phrase was *"progress-shaped without being progress."* The parameter lift pushed
three treewalkers onto their NEXT wall.

## The new top wall, from a re-measure rather than a guess

Ladder re-run at `594bd3c8c`: **12 of the 38 remaining failures share ONE root cause, and
it is a silent-wrong-function bug, not a missing feature** —
`bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name`, now claimed and in
progress. Same concentrated shape `yield` had, which is the encouraging part: the tail
keeps resolving into single levers instead of fragmenting.

*(Denominator caution: "38 remaining" is the full ladder at that sha. Do not reconcile it
against the older 6/48 or 7/33 by arithmetic — those were different scopes.)*

## Track B: a float parser that is now 27x-1118x faster

`StrToFloat` got **two** independent wins. First, `TryStrToFloat` was calling the parser
**twice** with different defaults and comparing the answers, because the parser had no
failure channel — a flat **2x on the entire family**, nothing to do with floats. Then
**Eisel-Lemire** landed: **27x to 1118x** outside Clinger's window, safe because Lemire
*declines* rather than guesses, so the exact path still answers everything it will not.

Reported honestly again: the two rows the ticket **named** ("small" 1e-310, "subnormal"
1e-320) did **not** move — both are subnormal, where Lemire declines by construction, as
Go and Rust do. Remainder rescoped as a big-integer rewrite of `ExDecNearest`. Also kept
visible: the Clinger fast path came out **5% slower** on code layout.

## A real compiler bug you would not otherwise have seen

A Track T **bench row-count drop** (27 rows where 30 were expected) turned out not to be
harness noise: **pxx could not compile its own source at `-O0`** — `error: code overflow`.

And the fix inverted the ticket. Measured, all four levels sat at **88-90% of the 8 MB
cap** (`-O0` 8 394 698 B vs a 8 388 608 cap — over by 0.07%). **`-O0` was simply first
across a line every level was standing on, and ordinary growth would have taken the
DEFAULT build down next.** Cap now 16 MB, default at 44%.

**The uncomfortable part, which is now recorded:** "it passes the self-host gate" is
evidence the compiler compiles itself **at one optimisation level**, not that it compiles
itself. I used that reasoning to argue the bench red could not be a compiler problem. It
was true and could not speak to the case.

## Decisions waiting for you — now TEN, three of them new

| prio | ticket |
| --- | --- |
| 88 | `decide-how-a-compiled-def-carries-its-signature-when-boxed` |
| 62 | `decide-xml-etree-thin-tree-model-or-a-real-xml-library` |
| 58 | `decide-which-minix-is-the-target` |
| **55** | **`decide-should-the-gate-prove-self-compile-at-more-than-one-o-level`** (new) |
| 55 | `decide-what-an-unwired-test-may-assert` |
| 50 | `decide-staff-track-c-to-unblock-own-language-first` — a **staffing** fork, yours alone |
| 50 | `decide-finalize-noop-vs-refusal` |
| 45 | `decide-unary-minus-widening-in-the-default-dialect` |
| 40 | `decide-one-answer-to-have-i-already-compiled-this-unit` |
| 40 | `decide-nilpy-exec-injects-a-builtins-key` |

## State on waking

- **frank2** is on the new top wall (claimed in `working/`).
- **frank3** stopped after two landings, on an offer I made it — B's queue below the
  rescoped float work is p20 ULP items.
- **Track T is UNSTAFFED** — plexus-T closed its session after handing off the `-O0` bug.
  Nothing is watching the matrix until you restart it.
