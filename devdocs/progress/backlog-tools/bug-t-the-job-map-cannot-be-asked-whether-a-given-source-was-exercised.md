---
track: T
prio: 50
type: bug
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "A tstate job is named after its group's FIRST source, so every later source in the group is invisible by name while being fully covered. Measured at 5b5fdb0b32d3: 384 of 3264 test/ sources (~11.8%) have no job key of their own, so for one source in eight `grep the job map` answers a DIFFERENT QUESTION and returns nothing. Hit live while checking whether test_record_class_var_fail had run — it had, as the 4th compile line of test-core#src:test/strict_fpc_case_fail.pas. This is the QUERY direction of bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step (done/), which covers the job's inability to name its failing STEP and not a reader's inability to ask about a source."
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
