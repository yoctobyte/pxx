---
track: A+T
prio: 55
type: bug
blocked-by: [chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it]
summary: "Makefile:49 is `TESTTMP ?= /tmp` — a fixed path, not per-checkout and not per-PID. Every agent's suite writes its test binaries to the same names in the same directory, so two concurrent runs on one box overwrite each other's artefacts. The failure mode is a wrong verdict, not a crash. CORRECTED 2026-08-29 (see body): testmgr ALREADY privatizes recipe /tmp paths per PID, so this is true only of bare `make`; the recipe half closed in b2cab6b6b; and the proposed fix would blind four testmgr expressions at once — blocked on the prerequisite."
status: done
---

# `TESTTMP` defaults to a path every checkout shares

Filed 2026-08-29 by frank-coordinator, from a candidate frankB named and
explicitly declined to assert as a cause. **This ticket is not that cause.**
frankB's two killed suite runs remain unexplained and this is filed on its own
merits, because the hazard is real whether or not it produced those kills.

## The fact

```make
# Makefile:48-51
# passing TESTTMP=$$(mktemp -d) on the command line.
TESTTMP ?= /tmp
$(shell mkdir -p $(TESTTMP))
export TESTTMP
```

`/tmp` is a fixed, machine-global path. It is not per-checkout, not per-user,
not per-PID. Every recipe that builds a test binary writes it to
`$(TESTTMP)/<name>` — and the names are stable across checkouts, because they
are derived from the test's own name.

So two suite runs on one box, in two different trees, write **the same absolute
paths**. There are currently six agent checkouts plus Track T's watcher clone on
this machine.

## Why it is worse than a crash

The two runs do not conflict noisily. Run A compiles `foo` to `/tmp/foo`; run B
overwrites `/tmp/foo` with its own build; run A then executes B's binary and
compares B's output against A's expectation. **The result is a verdict, and the
verdict is about the wrong binary.**

That is the generator-family signature and it is why the priority is not lower:
*a red from a collision and a red from a real defect produce the same reading*,
and neither the log nor the report names the tree the binary came from. A green
from a collision is available too, if the two trees happen to agree.

The cost is not the lost run. It is that a collision-red sends someone bisecting
a defect that does not exist, and a collision-green retires a real one.

## The mechanism to fix it already exists, one line above the bug

Line 48 documents `TESTTMP=$$(mktemp -d)` as the way to get an isolated
directory. It is available, it is correct, and it is not the default. **A
documented trap is not a guard** — the comment tells you the hazard exists and
then leaves you in it unless you knew to opt out.

## Direction, not a prescription

The obvious shape is to default `TESTTMP` to something that cannot collide —
derived from the checkout path or a `mktemp -d` per invocation — rather than
requiring every caller to remember. Two things to weigh before doing that, and
they are why this is a direction and not a patch:

- **Something may depend on the shared path.** Cross-checkout reuse of a built
  artefact would be silently load-bearing today and would break loudly. Grep for
  hardcoded `/tmp/` consumers outside the Makefile first, including in the
  tooling, before changing the default.
- **An expected-output file must never contain an absolute `/tmp` path**,
  because testmgr rewrites those. If the default becomes a per-run directory,
  check that nothing bakes the old one into a recorded expectation.

## Ownership

`A+T` on the two-axes model: **A** is the file-lane (`Makefile`), **T** is the
work-tag (test-harness integrity). Same split as
`bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing`, and
for the same reason — the subject is the harness, the file is A's.

**Sequencing note:** frankB holds `Makefile` for the 474-row assertion
conversion as of 2026-08-29. This ticket is a natural follow-on for whoever
holds that file next, but it must **not** be folded into that batch: a
mechanical conversion diff that also changes where every test writes its output
is no longer mechanical, and the one hunk that broke something becomes
invisible in it.

---

## 2026-08-29 — measured by Track T. The hazard is real but much narrower than
## filed, half of it is already closed, and **the proposed fix would break the
## harness.**

Taken as the ticket's own instruction — *"Grep for hardcoded `/tmp/` consumers
outside the Makefile first, including in the tooling, before changing the
default."* That grep is the whole content of this note, and it changes the
answer.

### 1. testmgr ALREADY privatizes every recipe-level `/tmp` path

```python
RUN_TMP = "/tmp/testmgr-scratch-%d" % os.getpid()
...
body = TMP_RE.sub(lambda m: m.group(0) if m.group(0) in pinned
                  else RUN_TMP + m.group(0)[len("/tmp"):], ln)
```

Per-PID, applied at execution to every recipe line. So the ticket's central
sentence —

> two suite runs on one box, in two different trees, write **the same absolute
> paths**

— **is not true of testmgr-driven runs**, which is how the watcher, `gate.sh`
and `testmgr --tier` all run. The rewrite exists precisely because two runs
"would interleave in each other's self-host chains and corrupt both (observed
2026-07-08: fixedpoint byte-diff with a clean tree)".

The exposure is **bare `make` invoked by hand**. That is a real hazard and worth
closing, but it is not six agent checkouts colliding continuously: CLAUDE.md's
per-fix loop is `make compiler/pascal26` plus a single repro, and the full
suites are refused outright by `.claude/hooks/no-full-suite.sh` for every lane
but T.

### 2. The recipe half was closed two weeks ago

[[chore-makefile-testtmp-parameterize]] landed 2026-08-14 (`b2cab6b6b`) and
routed the recipes through `$(TESTTMP)`. Its own closing note is exact: *"a
green gate here means the recipe half is closed, and nothing more."*

### 3. What is actually still open is the RUNTIME half — and it is already filed

60 distinct `/tmp` paths are baked into compiled sources across 37 files
(63 minus the 3 the Makefile also names, which are deliberately *pinned* so the
producer and consumer keep agreeing). Nothing rewrites a string constant inside
a binary, so **those do collide even under testmgr**. That is
[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]], p35, and it is where
this ticket's real residual hazard lives.

`tools/testmgr_hardcoded_tmp_devtest.py` already guards against new ones, and is
RED today on exactly one new instance —
`test_nilpy_class_named_like_an_rtl_record.npy` writing
`/tmp/pxx_nilpy_rtlrec_probe.txt` — filed to Track N this morning.

### 4. THE PROPOSED DIRECTION WOULD BREAK TESTMGR, and testmgr says so in advance

This is the finding that matters. Four expressions in `make_dry_run()` hardcode
the literal `/tmp` prefix as it appears in `make -n` output, with this comment
sitting on them:

> That is safe today and must stay a deliberate choice: […] `$(TESTTMP)`, whose
> default is `/tmp` precisely so this keeps matching. **If anything ever runs
> `make_dry_run()` with `TESTTMP` set elsewhere, all four go blind AT ONCE and
> fail silently** — no privatization (concurrent runs collide again) and no
> producer/consumer merge (which is how `test-core#555/#556` went red on
> 2026-07-12). **Teach them the value before setting it; do not set it and
> hope.**

So defaulting `TESTTMP` to a `mktemp -d` — the ticket's stated direction — would
**remove the isolation that currently exists** and simultaneously break the
job-dependency merge, silently, in the direction where a red and a real defect
read identically. It would make the exact problem this ticket is about worse
while appearing to fix it.

The `/tmp` default is not an oversight. It is load-bearing, and the comment
above it is the guard.

### Recommendation

Not "change the default". The order is:

1. **Teach testmgr the value** — derive `TMP_RE`, the two `.so`/loader
   expressions and `RUN_TMP` from `TESTTMP` rather than a literal. Pure Track T,
   and it is the prerequisite the code names. Filed as
   [[chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it]].
2. *Then* the Makefile one-liner becomes safe, and it is a small Track A change.
3. Separately, [[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]] is the
   half no default can fix.

Until step 1 lands, **the correct action on this ticket is to change nothing.**

### On the filing itself

The ticket was explicit that it was filed on its own merits and not asserted as
the cause of frankB's killed runs, and that restraint was right — the measured
answer is that it could not have been, for a testmgr-driven run. Recording that
because a candidate cause that is *ruled out* is worth as much as one confirmed,
and it is the half that usually goes unwritten.

---

## 2026-08-30 — FIXED, in two halves, by pxx-a5. The prerequisite turned out to
## be only half-landed, and the missing half was the failure it was written to
## prevent.

### File declaration (asked for in the dispatch, recorded here rather than in a message)

Files touched: **`Makefile`** (the `TESTTMP ?=` block only, lines ~40-70) and
**`tools/testmgr.py`** (`BASE_ENV_KEEP`), plus a new
`tools/testtmp_agreement_devtest.py`. Clear of frankA (`pasparser_*.inc`) and of
frank-optimize-b4 (`ir_codegen.inc`) — no overlap in either direction. Nothing
under `compiler/**` was opened. An unfiled scope reads as covered, so: the 474-row
assertion conversion in `Makefile` was NOT touched and this change was not folded
into it, per the sequencing note above.

### The prerequisite was landed but not finished — measured, not assumed

[[chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it]] is in
`done/`, and it did teach the MATCHERS: `TESTTMP` is read once (testmgr.py ~920)
and `TMP_RE`, the three `make_dry_run` expressions, `_REASON_TMP_RE`, the pinned
root and `RUN_TMP` are all derived from it.

It did not teach the PRODUCER. `job_env()` is an **allowlist** — `ENV_ALLOW`
plus the `PXX_`/`TESTMGR_`/`LC_`/`QEMU_` prefixes — and `TESTTMP` was on neither.
So the value moved the matchers and was then **stripped from the environment of
the make those matchers were written to read**:

```
parent TESTTMP=None       matchers=/tmp   make says=/tmp   AGREE=True
parent TESTTMP=<scratch>  matchers=<scratch>  make says=/tmp   AGREE=False
```

```
testmgr TESTTMP      = <scratch>
TESTTMP in job_env   = False -> None
```

That is precisely the state the code's own comment forbids — *"all four go blind
AT ONCE and fail silently — no privatization (concurrent runs collide again) and
no producer/consumer merge (which is how `test-core#555/#556` went red on
2026-07-12). Teach them the value before setting it; do not set it and hope."*
A prerequisite that reads the value and cannot pass it on is **not** the
prerequisite; setting the Makefile default on top of it would have produced
exactly the silent failure it was filed to prevent.

Worth naming as a shape: **the guard-comment was satisfied by the half that is
easy to see.** Reading the value is visible in a diff; passing it on is a
one-line absence in a list somewhere else, and nothing failed when it was
missing — the default was `/tmp` on both sides, so the two halves agreed *by
coincidence* and the coincidence was load-bearing.

### The fix, in order

**1. `tools/testmgr.py` — PIN, don't allowlist.** `TESTTMP` is now set into
`BASE_ENV_KEEP` ("set for every job regardless of what the parent had") rather
than added to `ENV_ALLOW`. The difference matters exactly in the common case: an
allowlist entry passes the value through only when the parent already has one,
so with a silent parent make would still fall back to its own default — which is
the whole hazard once that default is no longer `/tmp`. Setting it means the
Makefile's `?=` never fires under testmgr, so producer and matchers cannot
disagree *even after the default moves*. Agreement is now structural rather than
maintained.

testmgr's own default stays `/tmp` deliberately: `reap_stale()` and the stale
sweep find abandoned scratch by globbing that root, and a per-checkout root would
scatter abandoned runs where no run looks.

**2. `Makefile` — the default is now per-checkout.**

```make
TESTTMP ?= /tmp/pxx-testtmp-$(shell id -u)-$(notdir $(CURDIR))-$(shell printf '%s' '$(CURDIR)' | sha1sum | cut -c1-10)
```

Keyed on `$(CURDIR)` so two trees cannot collide, on the uid so two users cannot,
**stable within a checkout** because separate `make` invocations in one tree hand
artefacts to each other by path (a per-invocation `mktemp` would break that
pairing rather than isolate it — the reason the old comment gave for not doing
it, and it still holds). The basename rides in front of the hash so a leftover
directory is attributable to a tree by looking at it; a hash alone is not, and
nothing can reap these by liveness since the tree they belong to may be gone.

This governs **bare `make` only**, which is exactly the exposure the 2026-08-29
measurement narrowed the ticket to.

**3. `tools/testmgr.py` — and the same value written BACK into testmgr's own
process environment.** This half was missing from the first cut, and
`tools/gate.sh quick` is what found it — the run went RED with:

```
ok: /tmp/testmgr-scratch-3468135/pxx-testtmp-1000-pxx-1564e1dfa2/qc_nilpy26
sh: 6: /tmp/testmgr-scratch-3468135/pxx-testtmp-1000-pxx-1564e1dfa2/qc_nilpy26: not found
```

`make_dry_run()` is a **second** `make`, and it passes no `env=` at all — it
inherits testmgr's own environment. Pinning the value into `job_env()` reaches
the make that EXECUTES a job and not the one that READS it. With the default
still `/tmp` the two agreed by coincidence; the moment it moved, `make -n` named
the per-checkout root, `TMP_RE` matched it happily, and the privatizing rewrite
prefixed `RUN_TMP` onto an **already-rooted** path. The compile then succeeded at
the doubled path and the exec line, rewritten differently, did not find it.

`os.environ["TESTTMP"] = TESTTMP` at the point of reading fixes every call site
at once — there are four `make` invocations in that file and only one of them was
getting the pin. Deliberately set on the process rather than at each site: an
environment the whole process shares cannot go out of step with itself, where a
per-call `env=` can, and the next `make` invocation someone adds must not have to
know. `job_env()`'s allowlist still drops it, so the job half stays pinned in
`BASE_ENV_KEEP` — two mechanisms because there are two environments, not because
there are two policies.

**This is the part of the work worth keeping.** The first cut passed seven
guards, all of which I had verified would fail on the condition they named — and
it was still wrong, because every one of them exercised `job_env()` and none of
them exercised the other `make`. *A guard suite that agrees with itself proves
the mechanism it samples, not the behaviour.* The 30-second gate was the second
data point, and it disagreed.

### Guarded: `tools/testtmp_agreement_devtest.py`, 9 guards

Auto-collected by `tools-devtest` (it globs `tools/*devtest*.py`). Every guard was
verified to FAIL on the condition it names, not merely to pass on the fix:

| condition | result |
| --- | --- |
| job-env pin removed, new default kept (the dangerous combination) | 4 red, incl. *"the make testmgr spawns writes to `/tmp/pxx-testtmp-…` while every matcher hunts `/tmp`"* |
| process-env pin removed | 2 red, incl. the dry-run one that the gate found and the first seven missed |
| both pins kept, default reverted to `/tmp` | 1 red — *"no longer mentions `$(CURDIR)`, so it is not per-checkout"* |
| all in place | 9 green |

The halves are only safe together, and each guard says so in the voice of the
failure rather than of the code.

**One instrument error, recorded because it is the same shape as the bug.**
The two new guards went red on their first run against a CORRECT tree: the
harness's `load_testmgr()` restored the parent's environment in a `finally`, and
with the parent silent that restore *deleted the pin the module had just
written* — the tidy-up removed the thing being measured. Had I trusted the first
red I would have "fixed" working code. The restore is gone and the reason is in
the docstring.

### Residual, deliberately NOT taken

Four recipe lines still name a literal `/tmp` and so are untouched by any default
(`Makefile:437`, `:13608`, `:15916`, `:15917`). **"Convert the rest to
`$(TESTTMP)`" is not a safe blanket follow-up**, and that is the finding: at
least two of the four are pinned to a literal baked into a compiled test SOURCE
(`rm -f /tmp/test_nilpy_sqlite_crud.db` must keep matching what the `.npy`
writes), so converting them would silently stop the cleanup rather than move it.
Whoever takes that must check each against its source, one at a time. The
source-side half remains
[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]], which no default can
fix.

Nothing else on this box consumes a `$(TESTTMP)`-produced artefact by hardcoded
path: every tool that both runs make and names `/tmp` (`gate.sh`,
`fpc_diff_probe.sh`, `run_fgl_corpus.sh`, `selfhost_fixedpoint.sh`,
`selfcompile_odiff.sh`, `run_sqlite_thread_test.sh`, …) owns its own scratch via
`mktemp -d` or `$$`. Checked before changing the default, as the ticket
instructed.

### Gate

`make compiler/pascal26`: `converged after 1 round(s)`, self-host fixedpoint
verified, `1bca19929e04`. `tools/gate.sh quick` RED on the first cut (that is
how half 3 was found) and re-run to completion after it. The four tmp-adjacent
devtests (`testmgr_hardcoded_tmp`, `expect_same`, `job_reason`,
`testmgr_tmp_advice`) and the two contention ones green, plus the new 9.

Note for whoever reads the gate log: it also reported *"Track T tooling is
running here (2 process(es)), load 11.17"*, so the timings in it are 2-3x a
quiet box's and are not a signal.

## Log
- 2026-08-30 — resolved, commit c9699f7e2.
