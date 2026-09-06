---
found: 2026-09-06
found-by: frankB
slug: bug-t-a-tier-job-identifier-is-a-selector-doing-double-duty-as-a-label
track: T
prio: 55
type: bug
status: backlog-tools
owner: ""
blocked-by: []
summary: "TWO LAYERS, and the second is the more dangerous one. (1) A tier job's printed identifier is a SELECTOR doing double duty as a LABEL: `job_selector()` returns `<target>#src:<srcs[0]>` and its docstring says why — the first source is *stable across renumbering* — which is right for a `--job` argument and no reason at all for the string a human reads, titles a ticket after, or is handed as an assignment. Because every `$(COMPILER)`-dependent job inherits that target's prerequisites at the head of its source list, a multi-source job routinely names a file that is fine; three rows in `20260906T183724Z-6d04b14-seven.md` do it and three sessions hit it independently in one evening. It is right about a THIRD of the time, which is worse than never, because the times it is right teach you to trust it. (2) The stored REASON is not the subject either: `job_reason()` returns the log TAIL (correctly — a signature list goes stale silently) and `stub_reason()` cuts it to 200 chars, so `test-emit-obj`'s reason was THREE SUCCESS ECHOES, one of them a Makefile `echo` that prints only after the assertion it names has passed. It was read as the subject and propagated to three sessions. A reason is more dangerous than a name: a name is obviously an identifier, a truncated tail reads as a finished sentence about the subject while being a receipt for the last step that SUCCEEDED. THE EVIDENCE ALREADY EXISTS ONE FIELD AWAY — `failed_step()` and `step_sources()` record the failing recipe line and its own sources per red, with `step_src` deliberately \"\" rather than falling back — so layer 1 is not 'build a mechanism'. Layer 2 is a READING failure and explicitly NOT a proposed patch; the tail is the right return value."
---

# The job identifier is a selector, and it is being read as a label

## The two jobs one string is doing

`tools/testmgr.py`, `job_selector()`:

```python
    # Prefer the first source it compiles (stable across renumbering); fall
    # back to the positional name for jobs that name no source
    return "%s#src:%s" % (job.target, srcs[0])
```

**As a selector that is correct and the docstring's reason is a good one.** A
`--job` argument must survive somebody inserting a recipe line, and `srcs[0]`
does while `#00` does not.

**As a label it is arbitrary.** `srcs[0]` is decided by Makefile prerequisite
order, so every `$(COMPILER)`-dependent job inherits that target's
prerequisites at the head of its list, and a job about object emission gets
named after a shell script.

The identifier is not an internal key. It is the row a human reads in a tstate
report, the string a ticket gets titled after, the thing a coordinator hands a
peer as an assignment, and the key a `still_red` comparison is made on.

## Three instances in one report, from three sessions

`devdocs/progress/tstate/reports/20260906T183724Z-6d04b14-seven.md`:

| printed identifier | what it is about |
| --- | --- |
| `test-emit-obj#src:tools/compiler_srchash.sh` | object emission; srchash appears nowhere in the failure |
| `test-zlib#src:tools/compiler_srchash.sh` | the zlib corpus being absent |
| `test-fpjson#src:tools/install_lib_candidates.sh` | a duplicate-definition warning in `test/fpjson/testutils.pas` |

Three sessions reached it independently on 2026-09-06 from three different
rows, which is what makes it positional rather than a coincidence of one
recipe.

## The evidence is already recorded, one field away

This is the part that changes what the fix is. `testmgr.py` already has:

- **`failed_step(job)`** — reads a marker file `script()` writes before each
  recipe line, so *which* line went red is a READ, not an inference.
- **`step_sources(line)`** — that line's own sources, and **`""` when the line
  names none**, deliberately not falling back to the job's other sources. Its
  comment says why: *"the fallback IS the defect, because the job's other
  sources are what sent three tickets to the wrong lane."*
- **`step_src` / `step_line` / `step_i` in the report JSON**, filled for every
  red, and `twatch.py`'s `step_fields()` / `step_note()` render it as a
  separate `Failing step:` bullet — deliberately separate from `Test source:`,
  because they answer different questions.

**So the routing evidence exists, is correct, and is already rendered — and the
identifier does not use it.** A reader who scrolls to the bullet is served. A
reader who reads the row, or a coordinator who copies it into an assignment, is
not.

## The `reason` field does not rescue it either

The stored detail is a **fixed-width tail of captured output**, not a failure
list. `test-zlib`'s reads `corpus absent: library_candidates/zlib.` while
sitting under a **FIXED** heading. `tools-devtest#00`'s named three `twatch_*`
progress lines — printed *before* each devtest runs, for files that may well
have passed — cut mid-word, and it could never have named the devtest that
actually failed, which sorts earlier in the glob. **Absence from that field is
uninformative in both directions**, and a reader who takes it as "the failing
sources" gets a confident wrong answer.

## The fork, and the measurement that settles it

Do NOT change what `job_selector()` returns — that would break `--job`
stability, which is the property it was written for.

The question is what the DISPLAYED identifier should be for a red, given that
`step_src` is already sitting beside it:

- **Show the step's source when there is one**, falling back to the current
  string. Cheap, and it is right exactly when `step_src` is non-empty.
- **Suppress the source entirely for multi-source jobs** (`test-emit-obj#00`).
  Honest, and it discards a name that is right for the many jobs whose first
  source IS the subject.

**The discriminator is a census nobody has taken: across one full tier, for how
many multi-source jobs is `srcs[0]` actually the subject, and for how many reds
is `step_src` non-empty?** If `step_src` is usually populated, option one is
strictly better and nearly free. If it is usually `""` — a `readelf` assertion,
a bare binary run — then the identifier cannot be repaired from it and option
two is the honest answer. Take the census before choosing.

## What must not happen

Do not reorder Makefile prerequisites so the interesting source sorts first.
That makes the identifier right by accident, one Makefile edit away from being
wrong again, and moves a real dependency order to satisfy a display string.

## Related, not a duplicate

`chore-t-split-lib-test-into-jobs-that-name-what-failed` [T p45, low-prio] is
about SPLITTING one bundled job so each piece names its own source. This is
about the identifier every multi-source job already has. Fixing either does not
fix the other.

## The third witness — and the number that makes this worse than a broken name

frankH, reading the job listing for the full matrix (command elided; this file
is scanned by the suite guard):

> `test-zlib#00` carries the SAME first source as the `test-emit-obj` row:
> `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +4`. Two different
> targets, two different failure modes, one identifier — so
> `#src:tools/compiler_srchash.sh` cannot be describing either of them. The
> neighbouring row in the same listing, `lib-test#87`, leads with
> `test/lib_zlib.pas`, which is a genuinely descriptive first source; **so the
> identifier is right about a third of the time, which is worse than never,
> because the times it is right teach you to trust it.**

That last clause is why this is a bug and not a cosmetic complaint, and it is
CLAUDE.md's own rule arriving from the data: *an 80%-accurate name is worse
than a 0%-accurate one — the part you sample confirms it.*

## LAYER TWO: the REASON is not the thing either, and it is the more dangerous half

frankD, closing `test-emit-obj#src:tools/compiler_srchash.sh` (green at HEAD
`2699f5769`, fixed above the tree by `fc000b076`).

`job_reason()` returns **the log's TAIL**, by design, and its docstring gives a
good argument for it: a signature list goes stale silently and then reports
nothing for shapes nobody has met, while a tail is true for every shape.
`twatch.py:stub_reason()` then cuts that to `CASCADE_REASON_MAX = 200` for a
cascade bullet. For this row the three surviving fragments were:

```
ok: $TMP [code=470952B …] | test-emit-obj: an i386 object's file-scope
initialisers run under a gcc -m32 main | ok: $TMP [code=186531B …]…
```

**All three are success echoes.** The middle one is the Makefile's own `echo`
on the line *after* the assertion it names — it prints only once that check has
PASSED. It became "the failing thing" in the srchash write-up because it was
the only human-readable sentence in the string; the other two are compiler
statistics that do not look like a subject. The real failure was the assertion
immediately after the third fragment: `i386 .text still has $abs absolute
relocation(s)`.

So the write-up produced to teach *"the row name does not name the failing
thing"* corrected name → subject and then **made the identical error with
reason → subject, one layer up** — and it propagated to three sessions.

> **A REASON IS MORE DANGEROUS THAN A NAME.** A name is obviously an
> identifier. A reason looks like content — and a truncated tail is the worst
> of the three, because it reads as a finished sentence *about the subject*
> while being a receipt for the last step that SUCCEEDED.
>
> The rule is one sentence: **read the last fragment as "everything up to here
> worked" and go to the recipe line AFTER it.**

**This layer is NOT a proposed patch.** The tail is the right thing for
`job_reason()` to return, and the untruncated 400-char form in
`tstate/<host>.json` may well contain the error line the 200-char cut removed.
The failure is in the READING. It belongs here because it is the same defect
one level up — the identifier and the reason both describe something other than
the defect — and because a fix to the identifier that leaves the reason
un-annotated moves the trap rather than removing it. Written up in full in
`regression-test-debug-g-compiler-srchash-2.md`, with the superseded table row
marked inline so a grep-lander cannot take the old sentence.

## A fourth case, different mechanism, same shape

`test-zlib#src:tools/compiler_srchash.sh` appeared under **FIXED** with the
stored reason `corpus absent: library_candidates/zlib.` — traced by frankS to
`CORPUS_RE`'s character class swallowing a sentence-ending full stop, so the
row self-skipped on a box that has had the corpus since 2026-08-29 and **the
skip was hiding a green**. Not `srcs[0]`, and worth counting anyway: four rows
in one report where the printed identifier, the stored reason, or both are
about something other than the defect.

## Adjacent, and deliberately not folded in

frankD, on the row they just cleared: it can go green **by accident** — one
extra unrelated local in `PXXIoCheck` moves `code` off `-0x10` and the absolute
relocation count goes 1 → 0 with the defect untouched. They confirmed this
particular green is real by checking the load-bearing condition in the artefact
(`8b 45 f0` still at 28f22, store converted anyway, 0 absolute vs 587
PC-relative). **A row whose verdict moves with unrelated stack layout is a
different family from a row whose name is wrong** — that is a guard whose
expected value collides with an accidental one, not an identifier problem — so
it is recorded here as a pointer and not merged in. It wants its own ticket
against the assertion, phrased as a relation rather than a count.

## Related tickets, so nobody merges them later

- `bug-t-a-recipe-cannot-declare-its-own-skip-a-coverage-hole` [T p45,
  frankS] — a recipe that self-skips for a coverage-shaped reason has no way to
  say so. States outright that it did NOT cause the `skip_holes` 2-vs-7 gap
  (that was an emitter/classifier prefix mismatch, fixed separately). **Two
  different gaps in one number; do not merge them.**
- `chore-t-split-lib-test-into-jobs-that-name-what-failed` [T p45, low-prio] —
  splitting one bundled job so each piece names its own source. Fixing either
  does not fix the other.

## 2026-09-06, frankuser — the misnomer is PERSISTED IN SLUGS, not just printed

A fourth session hit layer 1 the same evening, and the new fact is that the bad
name does not stay in a log line. **It becomes the ticket slug, which is the
search key.**

Nine auto-filed regression tickets on disk are named `#src:tools/compiler_srchash.sh`,
across **seven distinct jobs** — `test-debug-g` (×2), `test-cjson`, `test-fgl`,
`test-lua`, `test-lua-cross` (×2), `test-emit-obj`,
`test-sqlite-threads-aarch64`. One script, seven unrelated subjects, because it
sits at `srcs[0]` for everything that depends on `$(COMPILER)`.

**The cost, measured rather than argued.** `tools/compiler_srchash.sh` was
genuinely edited tonight (`79264f396` — a bash shebang meant the stamp guard
compared two absences and called them equal). Grepping the backlog for
`srchash` afterwards returns nine regression tickets, and **every one reads as a
possible fallout from that fix.** They are not: the newest was found
`2026-09-06T04:48:59Z`, seventeen hours before the change. Two tool calls to
establish that, and the discriminator was a timestamp, not anything about the
subject.

**This is the specific way an 80%-accurate name is worse than a 0%-accurate
one.** A log line is read once by the person who ran the job and has the run in
front of them. A slug is read by everyone afterwards, out of context, forever —
and it is what `grep` matches, so it decides who *finds* the ticket as well as
who is misled by it. The nine will still be answering the wrong question long
after the run that minted them is gone.

**Consequence for the fix, not a new ask:** whatever layer 1 lands on, the slug
generator should take it too. The archive is where a wrong name compounds, and
renaming these nine afterwards is cheap only while they are still open.

The ticket's own line holds and this is an instance of it — right about a third
of the time is what teaches you to trust it.
## 2026-09-06, frankH — the label manufactures a cluster that does not exist

Measured while looking for the reds behind
[[umbrella-one-full-tier-run-with-no-red-tier]], and worth adding because it is
a cost this ticket did not yet name: the label does not merely fail to
identify a job, it **invents a shared cause between unrelated ones.**

Grouping today's 54 full runs on seven by red job name produced what looked
like a six-member family, all naming `tools/compiler_srchash.sh`, going red
together (`test-emit-obj` + `test-zlib` in 42 of 54, others joining):

    test-zlib#src:tools/compiler_srchash.sh
    test-emit-obj#src:tools/compiler_srchash.sh
    test-debug-g#src:tools/compiler_srchash.sh
    test-lua#src:tools/compiler_srchash.sh
    test-lua-cross#src:tools/compiler_srchash.sh
    test-fgl#src:tools/compiler_srchash.sh

Co-occurrence that tight reads as one condition with six faces, and the shared
name says what it is. It is neither. **The step those jobs share PASSES** —
the logs read `self-host fixedpoint: verified — 1 round(s), ... (stamp read
back; sources match it)` — and each job then fails further along its own line
for its own reason (`FAIL 00040.c` under `test-c-conform` for one, the gcc
oracle build for another).

They share a name because a job is named after its FIRST source, and all of
them depend on `$(COMPILER)`, whose recipe's first prerequisite is
`tools/compiler_srchash.sh`. One report (`20260906T161630Z-29c4052-seven.md`)
has **eleven** jobs carrying it, five of them `test-c-conformance*#shardN/6` —
so the collision is not even confined to one suffix shape, and a reader
filtering on `#src:` sees a subset without being told one exists.

**Why the co-occurrence is the trap rather than the tell.** Jobs sharing a
label also share a prerequisite, so they genuinely do fail together — whenever
the box is slow, or the tier is wide, the same set lights up. The correlation
is real and its cause is scheduling, not a defect. So the usual defence
("check whether they move together") CONFIRMS the wrong reading here.

The discriminator is the log line, not the name and not the correlation:
`devdocs/dev/handbook-rationale.md`'s *"a reason is more dangerous than a
name"*, one level up — here the name was more dangerous than the reason,
because the reason was three fields to the right in the same string and the
name was in the summary. Reading the recipe text the ticket quotes is not
enough either; that text is the same for all six.

Cost this time: one wrong root cause, caught before it was filed. The auto-filed
[[regression-test-debug-g-compiler-srchash-2]] is one face of this and its own
banner already says the job "names a MECHANISM rather than a subject" — which
is this ticket, arrived at independently by the auto-filer's heuristic.

### Correction to the section above, from frankuser's, landed the same hour

The section above argues *"the step those jobs share PASSES"* from the log line
`self-host fixedpoint: verified — ... (stamp read back; sources match it)`.
**Read against frankuser's finding, that sentence was not evidence of much:**
`79264f396` fixed a bash shebang in `tools/compiler_srchash.sh` that made the
stamp guard **compare two absences and call them equal**. So for the runs I
read, "sources match it" may have been a vacuous pass — the guard agreeing with
itself about nothing, which is this handbook's *"a guard that cannot fail is
not a guard, and it prints PASS"*, sitting underneath a section about names.

**The conclusion survives, by the other route, and that route is the one to
quote.** The six jobs fail at DIFFERENT later steps with different messages —
`FAIL 00040.c` under `test-c-conform` for one, the gcc oracle build for
another. That is what makes them unrelated. Their shared step's verdict is not
load-bearing and should never have been the first thing offered.

Two readings that agree are not two sources unless they can fail differently,
and "the shared step passed" and "the shared step is not the cause" fail
together. The differing failure messages fail differently from both.
