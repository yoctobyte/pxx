---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`split_jobs` keeps a producer with its consumer by union-find over literal /tmp paths, so a recipe that reaches its artifact through a shell variable (`$(TESTTMP)/$$bin` in a for-loop) exposes no shared token, is never merged, and runs under job isolation with a scratch dir where the artifact was never built. Third instance of the class the splitter's own comments describe."
status: done
owner: unassigned
---

# split_jobs misses a /tmp dependency reached through a shell variable

- **Type:** bug (test harness) — **Track T** (`tools/testmgr.py`)
- **Found:** 2026-08-18 by frank2-7e (Track N) while resolving
  [[regression-test-nilpy-callbacks]] — full evidence and the reproduction are
  in that ticket.
- **Filed, not fixed:** T owns the tool. The instance that was red is already
  fixed on the recipe side; this ticket is about the class.

## The gap

`split_jobs` cuts a recipe into independently-scheduled jobs, then merges a
producer with its consumer by union-find over **shared literal `/tmp` paths**
(`tmp_re`). A consumer that names its artifact through a shell variable exposes
no such token:

```make
for t in tkinter_facade:test_nilpy_tkinter26 ... ; do \
  src=$${t%%:*}; bin=$${t##*:}; \
  timeout 120 xvfb-run -a $(TESTTMP)/$$bin > ...
```

`make -n` yields `/tmp/$bin`, so the job's token set was `['/tmp/test_nilpy_tkcb26']`
— its own output only — while it RAN three binaries. No merge, no ordering, and
the job failed with `test_nilpy_tkinter26: not found` whenever it did not happen
to follow its producers in the shared per-run scratch.

## Why this is a class, not an instance

The splitter's own comments already record two members, both solved with
synthetic tokens: a `.so` located by **soname**, and a bare-`/tmp`
**`LD_LIBRARY_PATH`** consumer. The comment's own phrase — "invisible to a
filename scan" — describes this third member exactly. Each was found by a red
job rather than at authoring time.

## Suggested fix (T's call)

A **lint over the job table** rather than more token synthesis: flag any job
whose text reaches `/tmp` through a variable — `$(TESTTMP)/$$<var>`, `/tmp/$…` in
`make -n` output — and report it as an unmergeable dependency at authoring time.
Token synthesis has now been extended twice per discovered instance; a lint
catches the next spelling without predicting it, which is the property the
previous two fixes lacked.

Cheap corroborating signal: a job that runs a binary it does not compile is
suspicious on its own, independent of how the path is spelled.

## Not to be confused with

`bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic`
(T, p55). That gap is real and separate — a `timeout` inside a make recipe
genuinely cannot participate in testmgr's contention logic. It was the leading
hypothesis for `regression-test-nilpy-callbacks` and measurement falsified it
there (0.14 s against a 120 s ceiling); it should keep standing on its own
evidence (`crtl_exp2`), with that job removed from its supporting set.

---

## OPERATIONAL HEADS-UP FOR THE WATCHER — a selector id goes silent, by design

Relayed by the coordinator, because it changes a key `twatch` holds history under and
the failure mode is misreading a silence.

As of `9f11b405d`, the three tk jobs are merged into ONE ordered job whose first source
is `examples/tk/tkinter_facade.npy`. Consequence:

```
test-nilpy#src:examples/tk/callbacks.npy   →  no longer selects anything
```

That id is this repo's `regression-test-nilpy-callbacks` key and the one the open-
regression list has been carrying. **Its disappearance is the fix landing, not a job
vanishing or a suite silently losing coverage.** Coverage is unchanged — the same three
programs are compiled and run; they are now one job instead of three unordered ones, and
the merged job compiles all three binaries it runs.

Verified statically by the coordinator rather than by running the tier: the loop's item
list now spells each binary by full path, `tkinter_facade` first, so union-find has the
literal tokens it needs and the merged job's first source is the facade.

Two things follow for T:

1. When reconciling open regressions against a new sweep, treat
   `test-nilpy#src:examples/tk/callbacks.npy` as **closed by rename**, not as an
   untested job. If the reconciliation is automatic, this is the case that needs a
   human-visible note rather than a silent drop.
2. Any historical red/green series held under the old id belongs to the same coverage
   and should be carried onto the merged job's id if that is cheap. If it is not cheap,
   say so rather than losing it quietly — the history is what makes the next bisect
   cheap.

### A note on the lint suggestion above

The coordinator endorses it. Both earlier instances of this class (a `.so` found by
soname, a bare-`/tmp` `LD_LIBRARY_PATH` consumer) were closed by adding one synthetic
token per discovered spelling, and this is the third spelling. A per-spelling token
predicts the next one; **a lint over the job table does not have to**. The two checks
worth having are the ones this bug would have tripped on: flag any job that reaches
`/tmp` through a variable, and flag any job that RUNS a binary it does not COMPILE.

That is the normalise-don't-special-case call, and it also explains why the fix here
landed in the Makefile rather than in `testmgr`: the tool cannot resolve shell variables
in general, so the recipe stating its own paths is the normalising fix rather than a
second mechanism. The lint is what makes the recipe's obligation checkable.

## Resolved 2026-08-19 by Track T (plexus-T) — the lint is shipped and enforced

`tools/testmgr_tmp_var_devtest.py`, picked up automatically by the new
`make tools-devtest` target (limited + full tiers), so it runs rather than
waiting to be remembered.

**It flags `/tmp/$` in executable recipe text** — the spelling `tmp_re` cannot
match at all, since `$` is outside its character class, so the token is not
merely wrong but absent. That is the property both mechanisms rest on: union-find
merging (a producer with its consumer) and privatization (concurrent runs not
sharing a file). This is why the lint is the right shape and a fourth synthetic
token would not be: it does not have to predict the next spelling.

**Comment lines are excluded, and that was not cosmetic.** The first draft
flagged the very recipe that FIXED the callbacks case, because its explanatory
comment quotes the old `/tmp/$bin` spelling. A guard that trips on prose gets
muted, and a muted guard is not a guard — the rule `tstate_reader_devtest`
states, hit here within a minute of writing the check.

### It found a live instance on its first run

[[bug-n-tk-got-files-are-invisible-to-testmgr-privatization]] — **in the same
recipe whose earlier fix was believed complete.** `9f11b405d` spelled the
BINARIES by full path, which fixed the merge and closed the callbacks red. The
output capture files are still `$(TESTTMP)/$$src.got`, so the three `.got` files
are never privatized and two concurrent runs share them. The merge half is fixed;
the privatization half was never in scope and nobody noticed, which is precisely
this ticket's thesis about per-spelling fixes.

Filed for the owning lane rather than fixed here (T owns the tool, never the
recipe), and carried in the devtest's `KNOWN` list so the guard stays green
without the allowlist telling a lie — it prints the open instance on every run,
and prints a "remove it from KNOWN and close its ticket" line the moment the
recipe stops matching.

### The second suggested check is split out, not silently dropped

*"A job that RUNS a binary it does not COMPILE"* is prototyped and deliberately
not shipped: it yields 5-7 candidates depending on how recipe lines are
segmented, and segmenting made it WORSE, which is the tell that the rule is not
yet well-defined. Candidates and the reason are recorded in
[[chore-t-lint-a-job-that-runs-a-binary-it-does-not-compile]] (p30) so the next
attempt starts from data. The parent ticket calls it a "cheap corroborating
signal"; the enforced half is the one that covers the spelling that has bitten
twice.

### On the operational heads-up above

`test-nilpy#src:examples/tk/callbacks.npy` going silent is confirmed here as the
fix landing: the merged job's first source is `examples/tk/tkinter_facade.npy`,
which is the selector the job now carries, and the same three programs are still
compiled and run.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
