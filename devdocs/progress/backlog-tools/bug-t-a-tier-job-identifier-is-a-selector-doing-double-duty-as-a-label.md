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
summary: "A tier job's printed identifier is a SELECTOR doing double duty as a LABEL, and the two want opposite things. `job_selector()` returns `<target>#src:<srcs[0]>` and its own docstring says why — the first source is *stable across renumbering* — which is exactly right for a `--job` argument and no reason at all for the string a human reads. Because every `$(COMPILER)`-dependent job inherits that target's prerequisites at the head of its source list, a multi-source job routinely names a file that is fine: three rows in `20260906T183724Z-6d04b14-seven.md` do it, `test-emit-obj#src:tools/compiler_srchash.sh`, `test-zlib#src:tools/compiler_srchash.sh` and `test-fpjson#src:tools/install_lib_candidates.sh`, and three sessions hit it independently within one evening. THE INFORMATION ALREADY EXISTS ONE FIELD AWAY: `failed_step()` and `step_sources()` record the failing recipe line and its own sources per red, and `step_src` is deliberately `\"\"` rather than falling back to the job's sources — the right call, and it means the routing evidence is already there and simply does not reach the identifier. So this is not 'build a mechanism', it is 'the label is taken from the selector when a better field is already populated beside it'. What it costs: the identifier is what a ticket gets titled after and what a coordinator hands a peer as an assignment, and one seat had to be told in the same message not to start from the name."
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
