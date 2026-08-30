---
track: T
prio: 50
type: bug
status: done
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), triaging the fpc-bootstrap NEW-RED
summary: "job_reason() is the last 6 lines of a log's last 8KB. FPC's compiler.pas build emits 960 warnings, so for the fpc-bootstrap red of 2026-08-30 the six lines it kept were three warnings and three 'there were 1 errors' summaries — on two hosts independently. The reason names an error and does not contain it, which is the failure it was built to end, one level in."
owner: claude@plexus
---

# A red compile job's reason held six lines and none of them was the error

## The observation

`fpc-bootstrap#src:compiler/compiler.pas` went NEW-RED on **plexus** and
**seven** independently within the same window (2026-08-30 00:00Z / 2026-08-29
23:56Z). Both recorded the identical reason:

```
compiler.pas(1546,10) Warning: Variable "CCmdDefCount" does not seem to be initialized
 | compiler.pas(1557,10) Warning: Variable "CCmdUndefCount" does not seem to be initialized
 | compiler.pas(2003,54) Warning: Comment level 2 found
 | compiler.pas(2194) Fatal: There were 1 errors compiling module, stopping
 | Fatal: Compilation aborted
 | Error: /usr/bin/ppcx64 returned an error exitcode
```

Six lines. Three are warnings that are present in **passing** builds too (a
clean run at `b873393d707f` emits 960 warnings, "Comment level 2" among them, and
links fine). Two are FPC's own summary of an error it is not quoting. One is the
driver's exit code. **The error itself — the one line a Track A reader needs — is
not there**, and there is no way to recover it from tstate: the log lives on the
watcher's clone.

## Why, exactly

`job_reason()` (`tools/testmgr.py:1732`) reads `REASON_TAIL_BYTES = 8192` from the
end of the log and keeps the last `REASON_LINES = 6` non-empty lines. FPC emits
960 warnings and 238 notes for this build. The tail of that log is warnings by
construction, and the error is out of frame whenever more than five lines follow
it.

The docstring's reasoning for a tail over a pattern list is **right and should
survive any fix**:

> *Deliberately the log TAIL rather than a pattern match: a signature list goes
> stale silently and then reports nothing for the failure shapes it has not met
> yet [...]. What the job printed last is true for every shape.*

The defect is not that it takes the tail. It is that the tail is **all** it
takes, so a shape the tail does not cover has no second chance.

## Proposed fix — additive, not a replacement

Keep the tail exactly as it is, and **prepend** the last line matching a
conservative error signature (`Error:`, `error:`, `Assertion`, `Segmentation`)
when such a line exists and is not already in the tail — scanning further back
than 8 KB, since that is precisely the case that fails. Budget it inside
`REASON_MAX` by trimming the tail, so tstate's size contract is unchanged.

Then the reason for a shape the signature list knows is *strictly better*, and
for a shape it does not know it is *exactly what it is today*. A stale signature
list can then only fail to add something — never to report nothing, which is the
docstring's actual objection.

## Guard the fix needs

A devtest whose fixture is a synthetic FPC-shaped log: 1000 warning lines, one
`Error:` line, then the three summary lines. Today's `job_reason` must return no
error text for it (i.e. the guard fails against current code); the fixed one must
contain the `Error:` line. Plus a log with no error signature at all, where the
output must be byte-identical to today's — that is the guard that keeps the fix
additive.

## Status of the red that found this

**Healed, or never reproducible here.** Measured at `b873393d707f` on plexus with
the canary's exact command line
(`fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas`): **rc=0**,
215631 lines compiled, linked. None of the four shas in either host's candidate
range (`f49a2f5ff4ff`, `df9f8ef0e6d9`, `0fccc2ed862a`, `ddb6f03c1b29`) touches
`compiler/compiler.pas`; the only commit that does since seven's last pass is
`82a2aa50f`, which is comment-only and lands *after* both hosts' `bad` sha. Both
entries carry `bad_untestable: true`.

The job is `advisory` (`testmgr.py:2568`) — a notice for Track A, not a gate — so
nothing was blocked. What it cost was the triage: two hosts agreeing on a reason
that says an error exists and will not say which, when the sha it accuses is
already green.

Related: `bug-t-a-job-that-never-passed-on-this-box-can-never-earn-a-bigger-budget`
(same family — an instrument whose scope is invisible in its own output).

---

## FIXED 2026-08-30

`tools/testmgr.py` — `job_reason()` keeps the tail exactly as it did, and when
that tail contains no error of its own, prepends the last one found above it.

```python
if not any(substantive_error(ln) for ln in lines):
    for ln in reversed(scanned[:start]):
        if substantive_error(ln):
            lines.insert(0, ln.strip()[:REASON_ERROR_MAX])
            break
```

Three pieces:

- **`substantive_error(line)`** — matches an error signature *and* not
  `_REASON_ERRORLESS_RE`. That second half is load-bearing rather than tidy:
  the observed tail **contains** `Error: /usr/bin/ppcx64 returned an error
  exitcode`, so without it "the tail already shows an error" is true and the
  scan never runs. The fix would have been inert on the case that motivated it.
  A driver reporting that its child failed is the exit code with a prefix.
- **`REASON_ERROR_SCAN_BYTES = 1<<20`** replaces the 8 KB read — but only as the
  *search space*. The kept lines are still bounded by `REASON_TAIL_BYTES`,
  expressed as a line index (`floor`), so the selection this function has always
  made is unchanged line for line.
- **`REASON_ERROR_MAX = 200`** caps the recovered line at half the budget, so it
  can never crowd out the tail it is joining.

### The mechanism was not what the ticket said

The ticket implied 960 warnings push the error past the 8 KB byte window. **It
does not.** Reconstructing the log, the error sits **455 bytes from EOF** — well
inside the window — and is lost purely because **six lines follow it**, one more
than `REASON_LINES` allows. Raising `REASON_TAIL_BYTES` would have fixed nothing
here, and the first cut of the devtest asserted ">8 KB from EOF" and went red,
which is how this was caught.

Both mechanisms are real and now have one fixture each: the FPC shape (inside
the byte window, out of frame by line count) and a `deep.log` whose error is
134 KB from the end behind 4000 `inlined from` lines — that one is what makes
the wider scan window earn its keep. Neither is assumed; section 1 asserts the
byte offset and the line count separately.

### Guard

`tools/job_reason_error_devtest.py` — **32 guards, 0 FAIL**.

The additive claim is not asserted, it is **proved against an oracle**: the
devtest carries a verbatim copy of the pre-fix implementation and requires
byte-identical output for a diff with no error text, a tail that already names
its error, and a log shorter than the tail window. Copied rather than imported
so it keeps working after the original is gone.

Discrimination confirmed in both directions: the old code cannot see either
fixture's error (and returns warnings in its place, exactly as observed on two
hosts), and five content-free lines — the ppcx64 driver line, "There were 1
errors compiling module", "Compilation aborted", make's `*** ... Error 1`, bare
`Error 1` — are each required *not* to count, while seven real diagnostics
(FPC, gcc, assertion, segfault, undefined reference, panic) are required to.

Neighbouring suites still green: `job_reason_devtest.py`,
`testmgr_host_tool_skip_devtest.py`, `testmgr_calibrate_range_devtest.py`,
`testmgr_tmp_advice_devtest.py`.

### Not changed

`REASON_MAX = 400` and the tstate size contract; `REASON_LINES`; the tail-first
design and the docstring's argument for it, which is right and now states its
own exception.

## Log
- 2026-08-30 — resolved, commit 3c769e06e.
