---
track: T
prio: 65
type: bug
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "A tstate job is named after its group's FIRST source, so every later source in the group is invisible by name while being fully covered. Measured at 5b5fdb0b32d3: 384 of 3264 test/ sources (~11.8%) have no job key of their own, so for one source in eight `grep the job map` answers a DIFFERENT QUESTION and returns nothing. Hit live while checking whether test_record_class_var_fail had run — it had, as the 4th compile line of test-core#src:test/strict_fpc_case_fail.pas. This is the QUERY direction of bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step (done/), which covers the job's inability to name its failing STEP and not a reader's inability to ask about a source. RAISED 50->65 on 2026-09-05: two MEASURED wrong readings during one night of live tier triage, both with attributable cost — one key standing for six unrelated targets (sqlite-threads x4, uforth, emit-obj) so the tier's red DENOMINATOR was unknown until settled by hand, and one job's history SPLIT ACROSS TWO KEYS when its recipe changed, which made test-uforth look like it had never run and pointed at a ~6.5 week bisect window instead of the true 234 commits. The key is derived from the recipe's TEXT rather than from the job's subject, so it is both too coarse and too brittle. 2026-09-06 adds the third and worst failure mode, SILENT REPOINTING, and the same day CORRECTED ITS OWN MECHANISM -- see the two dated sections, the first of which is wrong and kept. `@N` indexes JOBS that share a first source, NOT occurrences of that source in the Makefile: three test-xtensa jobs begin with test/test_cross_record.pas (#84 3 lines, #138 6 lines, #147 115 lines), so `@3` is #147. That is STRICTLY WORSE than the version first filed here, because a Makefile occurrence can at least be counted by reading the file, while the job list is produced by the harness's own recipe grouping and is invisible in the source it indexes -- you cannot resolve the key without asking testmgr. Add a job that shares the first source earlier in the target and `@3` still resolves, still names a real row, and now names a different one: the verdict history stays attached to a key whose SUBJECT changed underneath it, with no error, no gap and no split to notice. MEASURED COST, this file's own author: I read `@3` as a Makefile occurrence, measured #138, and published a 'not reproducible' exculpation for #147, which was genuinely red. The subject is (target, abi, source) and all three are already in the recipe."
---

# The job map cannot be asked whether a given source was exercised

## The incident, and it is the instrument's own user falling for it

Checking whether `test/test_record_class_var_fail.pas` had run in full tier
`5b5fdb0b32d3`:

    >>> [k for k in jobs if 'record_class_var' in k]
    []

**Zero. And the file existed in that tree** (`git ls-tree 5b5fdb0b32d3 test/`
confirms it), so the honest readings were "it did not run" and "it ran under
another name", which are not the same statement.

It ran. It is the **fourth compile line** of
`test-core#src:test/strict_fpc_case_fail.pas`, a job group of seven-plus
sources named after the first one. The job is the tier's single red, so not
only was the source covered — it was the thing that failed.

**The reader who hit this had, minutes earlier, reported reading a result "off
the job map rather than from the report's absence" as a point of discipline.**
That reading was sound only because `c_crtl_wait.c` happens to own a job key.
The method was never checked for the property it depends on.

## The measurement

At `5b5fdb0b32d3`, seven, full tier:

| | |
|---|---|
| jobs in the map | 4255 |
| ...keyed by a source (`#src:`) | 4193 |
| `test/` sources in the tree | 3264 |
| **...with no job key of their own** | **384 (~11.8%)** |

**For roughly one source in eight, absence from the job map carries no
information about coverage.** The query does not error and returns the same
empty list it would return for a source that genuinely never ran.

## Why this is not the ticket that is already closed

`bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step`
(`done/`) is about the job's inability to say WHICH of its lines died — the
producer side, and `Job.script()`'s step-marker file fixed it.

This is the **consumer** side: a reader with a source in hand cannot ask the
published map whether it was exercised. The step marker does not help, because
the reader does not have the job name to look the marker up by. Same root
naming decision, opposite direction, and not covered.

## Routes

1. **Publish the group membership.** The report already renders
   `— test/a.pas test/b.pas +5`, so testmgr knows the full list; the state's
   `jobs` map keeps only the key. A sibling `job_sources: {job: [srcs]}` would
   make the question answerable with no change to job identity.
2. **A helper, so nobody hand-greps.** `twatch.py --covered <path>` returning
   the job and its status, or an explicit `NOT COVERED` — the third state,
   which is the whole point.
3. Not renaming jobs. Job identity is load-bearing for regression ranges and
   ticket citations, and `bug-t-a-job-named-after-its-first-source-file...`
   already ruled that out for good reasons.

**Route 1 is the cheap one and route 2 is what makes it usable.** Both are
strictly additive.

## The same mechanism at three scales, on one night

This is not a tstate quirk. Measured 2026-09-05, three instances, three
granularities, one mechanism — **a name that aggregates hides the ARITY of what
it names**, so a second cause inside the first is not merely possible, it is
ENCOURAGED:

- **the job group**: 7+ sources under `test-core#src:test/strict_fpc_case_fail.pas`,
  one status. `test_record_class_var_fail` was a distinct defect inside it.
- **the eight-red batch**: `unknown type: TMethod` across eight jobs read as one
  cause. frankH separated `test_record_class_var_fail` from it by compiling
  under the v404 pin (`2d6bfadd6` a verified ancestor) rather than letting it be
  absorbed — the only reason the two are known to be different.
- **the unit count**: 28-vs-24 earlier the same night, the same shape at a
  third granularity.

In all three the aggregate reported truthfully about ITSELF and silently about
its members. **Ask an aggregate how many things it is before treating its answer
as one thing.**

## The rule

**A map keyed by one member of a group answers about the KEY, never about
membership.** An empty result means "no job is NAMED that", which is a
statement about naming, not about coverage — and it looks exactly like the
answer you were hoping to rule out.

## 2026-09-05 (frankZ) — two live instances in one night's triage, with costs

Filed as a gap in what the map can ANSWER. Both of these are the map giving a
confident WRONG answer during live tier triage, which is the stronger case.

**Instance 1 — one key, six unrelated targets.** `COMPILER_SRCHASH` is a make
variable at the head of many recipes, so `extract_src` picked
`tools/compiler_srchash.sh` as the source identity for six different targets:
sqlite-threads x4, test-uforth, test-emit-obj. The report's `near:` text for all
six was the `self-host fixedpoint: verified` line PRECEDING the failure rather
than the failure. Reading the tier as "six jobs share a cause" was the obvious
inference and it was wrong — six distinct targets, six distinct causes. **Cost:
the tier's denominator was unknown until it was settled by hand.**

**Instance 2 — the SAME 13 jobs under two identities, and this one nearly bought
a six-week bisect.** `seven.json` carries both:

```
test-uforth#src:compiler/.pascal26.fixedpoint@1..13   status=absent  last_pass=cc411ceee30b
test-uforth#src:tools/compiler_srchash.sh@1..13       status=fail    last_pass=b8e3b3010249
```

The recipe changed, `extract_src`'s answer changed with it, and the job's history
**split across two keys** — the old ones stranded as `absent`, the new ones
carrying the record. Nothing errors. Both key families look like real jobs.

The cost was concrete: reading the stranded family made `test-uforth` look like
it had never run, which combined with a (separately wrong) inference to suggest
the regression could be anywhere back to 2026-07-21 — **a ~6.5 week window**. The
correct window is `b8e3b3010249..5b5fdb0b32d3`, **234 commits**, established
instead by reading the report itself (`tier: full`, `skips: 1`, zero `uforth`
mentions → it ran and passed).

**WHAT WOULD HAVE PREVENTED BOTH: a job key that is stable under recipe edits,
and a map that can be asked "was source X exercised in run Y" rather than
"what is the status of key K".** Instance 1 is the key being too COARSE (six
targets collapse onto one name); instance 2 is the key being too BRITTLE (one
job's history splits when its recipe is touched). Same root: **the key is derived
from the recipe's text rather than from the job's subject**, so it inherits every
property of the text including its instability.

Raising prio: filed on a plausible gap, now carries two measured failures with
attributable cost in one triage session.

## 2026-09-06 — the BRITTLE half, where `@N` is the only thing naming the ABI

Measured at `874e55d0b` (`compiler/pascal26` = `6cd631730cf470e8`, srchash
`426da166f0f1e3b3`, matching the tree) while clearing
`test-xtensa#src:test/test_cross_record.pas@3`.

`test/test_cross_record.pas` appears **six times inside the single `test-xtensa`
target**, and the occurrences are not repetitions — they are three different
ABIs, each with its x64 control:

| occ | Makefile | what it actually is |
| --- | --- | --- |
| 1 / 2 | 22954 / 22955 | default (Call0) ABI + control |
| 3 / 4 | 23385 / 23386 | `--xtensa-abi=windowed` + control |
| 5 / 6 | 23518 / 23520 | the `movsp` decode probe, windowed vs Call0 |

So for this job the **occurrence index is the only thing that names the
subject.** `@3` does not mean "the third time we happened to mention this file";
it means *windowed ABI*, and nothing in the key says so.

**The failure mode this adds is silent REPOINTING.** The two costs already
recorded here are a key standing for six unrelated targets (too coarse) and a
history split across two keys when a recipe changed (too brittle in the
*forward* direction — the key moves and the job looks new). This is the
*backward* direction and it is worse, because nothing looks new at all: insert
or delete one earlier compile line for this source and `@3` keeps resolving,
keeps naming a real row, and now names **Call0 instead of windowed**. The
verdict history stays attached to a key whose subject changed underneath it.
No error, no gap, no split — the archive simply starts describing a different
ABI under the old name.

`@N` over recipe text is an index into a list nobody promised to keep stable,
used as the identity of the thing at that index. The subject here is
`(target, abi, source)`, and all three are recoverable from the recipe that
already exists.

### Status of the row that produced this

Not reproducible at `874e55d0b`. All six occurrences measured green, including
the `movsp` pair with its positive control asserted and branched on
(windowed 14 `movsp`, Call0 0, both `-d in_asm` logs non-empty at 3689 / 3987
lines). Value and rc slots both green on occurrences 1-4.

**This is an exculpation, so it names its owner for the residual question:** I
cannot say whether the row was ever red, because `tstate/` is not in this
checkout (it lives on seven) and the key reached me through a report, not a
run of my own. Whoever holds the tier verdict owns "was it red, and what fixed
it" — from here the only defensible claim is that it is green now, at that
tree, with that binary.

## 2026-09-06, later — the mechanism above is WRONG, and the true one is worse

Kept rather than repaired, because a corrected claim with no history reads as a
current-looking assertion nobody will check.

**`@N` does not index occurrences of the source in the Makefile.** It indexes
**jobs whose first source is that file**. Three test-xtensa jobs qualify:

    test-xtensa#84    qemu        3 lines   test/test_cross_record.pas tools/expect_same.sh +1
    test-xtensa#138   qemu        6 lines   test/test_cross_record.pas tools/run_target.sh +1
    test-xtensa#147   selfhost  115 lines   test/test_cross_record.pas tools/expect_same.sh +4

The report's `+4` names `#147`. The section above reasoned from six Makefile
occurrences and concluded `@3` meant `--xtensa-abi=windowed`; `@3` is `#147`,
a 115-line selfhost job.

**Why the true mechanism is worse than the one first filed here.** A Makefile
occurrence is at least *countable* — wrong, but checkable by reading the file
the key appears to describe. The job list is produced by the harness's own
recipe grouping, is not visible anywhere in the Makefile, and cannot be
enumerated without running `testmgr --list`. So the key indexes a list that
does not exist in the artefact it names, and the only way to resolve it is to
ask the tool that generated it.

**Measured cost, and it was this section's own author.** I read `@3` as
occurrence 3, measured `#138` (green, and still green), and published a *"not
reproducible"* exculpation for `#147` — which was genuinely red, and had been
since `f49c0e11f` at 2026-09-05 19:48. Fixed at `0a96caf54`.

**The discriminator was in the report I was reading.** Its truncated log carried
`code=491372B / 446316B / 122648B`; every program I built came out `196460B`.
Nothing errored and nothing was hidden. **A discriminator being present is not
the same as a discriminator being consulted** — and a session reading its own
job's report is the least likely reader to notice a size column, because the
size is not what it came for.

**An exculpation is the class that never gets revisited.** A green nobody
re-checks and a "not reproducible" nobody re-runs are the same object: a verdict
that stops work. This one was caught only because a peer asked an unrelated
question about a different ticket and the answer required opening the archive.


## 2026-09-06 (frank-coordinator) — the LIVE blast radius is 5 open tickets, and one of them is this one

Asked after frankZ's `b0d7cd10e` whether `@N` being systematically misread affects every
ticket citing a job by index. **Measured rather than assumed**, across the ranked and backlog
folders only (`done/` is history and `tstate/` is the archive):

- **5 open tickets** cite a job key of the form `<job>#src:<path>@N`.
- **21 distinct keys** between them.
- One of the five is **this ticket**.

```
backlog/regression-cascade-6758c7ce7dbd.md
backlog/regression-cascade-b8e3b3010249.md
backlog-core/bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal.md
backlog-core/feature-a-a-refusal-is-a-claim-with-a-date-on-it.md
backlog-tools/bug-t-the-job-map-cannot-be-asked-whether-a-given-source-was-exercised.md
```

**So the defect is systematic and the live cost is bounded.** 128 further citations sit in
`done/` and are records of what a past session read, not instructions — CLAUDE.md's precedence
rule already says not to repair those, and repairing them would date a claim that should stay
dated.

### The pathological shape is visible in the key list, and it is worse than a generic source

Thirteen of the twenty-one are one file:

```
test-uforth#src:tools/compiler_srchash.sh@1 .. @13
```

`compiler_srchash.sh` is the FIRST SOURCE of **thirteen different jobs**, so for that file
`@N` carries **no information except position in a list the reader cannot enumerate** — the
job grouping is the harness's recipe grouping, invisible in the Makefile and unobtainable
without `testmgr --list`. Compare `test-xtensa#src:test/test_cross_record.pas@3`, where three
jobs share the source and the three are at least distinguishable by ABI once you know they
exist.

> **A key whose disambiguating component is a position in an unenumerable list is not
> ambiguous — it is unresolvable by hand.** That is the sharpened form frankZ arrived at, and
> `compiler_srchash.sh` is the instance that shows the ceiling: thirteen rows, one name, and
> nothing a reader can do with the number.

**This does not change the recommended fix** — subject is `(target, abi, source)` and all
three are already in the recipe. It bounds the migration: **5 open tickets to re-key**, not a
board-wide sweep.

## 2026-09-06 (frank-coordinator) — THE PROPOSED SUBJECT `(target, abi, source)` IS INSUFFICIENT, measured against the job table

frankuser asked the right question before anyone started the migration: *do the thirteen jobs
sharing `tools/compiler_srchash.sh` differ in target and abi, or do some collide on all three?*
**Some collide, and by a wide margin.** Measured with `PXX_ALLOW_FULL_SUITE=1 testmgr.py --tier
full --list` — a print-and-exit that runs nothing; the guardrail is a speed limit and this is
the one lookup that cannot be done any other way.

**68 jobs** have `tools/compiler_srchash.sh` as their FIRST source, across 31 prefixes:

```
13  test-uforth#corpus #core #coreplustest #doubletest #exceptiontest #facilitytest
    #localstest #memorytest #searchordertest #stringtest #coreexttest #toolstest #filetest
 6  test-c-conformance      6  -i386   6  -arm32   6  -aarch64   6  -riscv32
 1  each of 26 others (test-core, test-smoke, test-asm, test-nilpy, test-zlib, …)
```

> **The thirteen `test-uforth` jobs share target AND abi AND first source.** They differ only
> by **corpus suite** — which is not target, not abi, and not a source. `(target, abi, source)`
> **collapses all thirteen into one key**, and each `test-c-conformance` group of six likewise.
> The scheme fails at exactly the worst case the ticket's own key list points at.

### And the harness ALREADY assigns a unique key per job — the citation form throws it away

`--list` prints **4312 jobs**, every one uniquely keyed, and **not one of them uses the
`#src:<path>@N` form**:

```
test-xtensa#84    qemu       3 lines   test/test_cross_record.pas tools/expect_same.sh +1
test-xtensa#138   qemu       6 lines   test/test_cross_record.pas tools/run_target.sh +1
test-xtensa#147   selfhost 136 lines   test/test_cross_record.pas tools/expect_same.sh +4
```

So `#src:…@N` is a **report-side rendering**, not the harness's key, and it discards
information that already exists one command away. **The three xtensa jobs are separated by
job TYPE and by their FULL source list** — `qemu`/`qemu`/`selfhost`, `expect_same`/
`run_target`/`expect_same +4` — neither of which the `@N` form carries, and neither of which
is abi.

### The residual, which is why this is a specification and not yet a fix

**4259 of the 4312 keys are NUMERIC** (`test-xtensa#147`) and only **49 are NAMED**
(`test-uforth#stringtest`). The named ones are stable and meaningful. The numeric ones are
**brittle-FORWARD**: insert a job earlier in the target and every later index shifts, carrying
its verdict history onto a different subject — the same failure as `@N`, one level up, in the
harness's own key rather than in the report's rendering.

> **So there is no tuple of (target, abi, source) that works, and there does not need to be:
> the job already HAS an identity. What it lacks is a STABLE one.** The fix is to make the
> harness's key name the job (as `test-uforth#<suite>` already does for 49 of them) and to cite
> that key, rather than to derive a new subject from the recipe's contents.

**Bounds unchanged:** 5 open tickets to re-cite. The `done/` and `tstate/` citations stay as
they are.
