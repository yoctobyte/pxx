---
track: T
prio: 40
type: bug
blocked-by: []
summary: "A `resolved, commit PENDING-COMMIT.` citation that wraps onto a continuation line matches neither progress.py's PENDING_RE nor sync.sh's fill, and `check` stays silent. The ticket keeps the literal placeholder forever, sync reports a clean push, and nothing anywhere says the resolve has no sha."
status: done
owner: pxx-a5
---

# A wrapped resolve citation is invisible to BOTH check and fill

- **Type:** bug (silent no-op) — **Track T** (board tooling; `tools/progress.py`
  + `tools/sync.sh`). Filed rather than fixed: T owns the tool.
- **Found:** 2026-08-30 (frankC), resolving
  [[bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead]].

## Measured

The Log line was written wrapped, which is ordinary in these tickets:

```markdown
- 2026-08-30 — reproduced at HEAD before claiming (all three cells), fixed,
  resolved, commit PENDING-COMMIT.
```

- `tools/progress.py check` reported **no** pending resolves.
- `tools/sync.sh` pushed and printed *"pushed 1 commit(s), all verified on
  origin"* — with no `filled PENDING-COMMIT` line, which is also exactly what a
  ticket with no placeholder looks like.
- The file still contained the literal string `PENDING-COMMIT`.

Rewriting it as one line made `check` see it immediately, and the next sync
filled it. So the placeholder is not merely unfilled — it is **unseen**.

## Why this is worse than it sounds

`sync.sh` already carries a long comment about this exact family: the fill and
the detection were once two sed literals covering fewer spellings than
`PENDING_RE` knew about, *"so `check` could report tickets this loop was
structurally unable to fill, which is the exact shape of the bug that pair of
literals was written to fix."* That was fixed by moving substitution beside
detection — and **this is the same bug rotated**: detection and substitution now
agree perfectly, and are wrong together, so the disagreement that used to expose
it is gone.

The failure is silent in all three places a person would look. A resolved ticket
can sit citing a placeholder indefinitely while the board, the checker and the
sync all read as healthy.

## Fix sketch

A regex is the wrong instrument for the *guard*, because any regex has spellings
it misses. Add a **second, dumber check that does not share its assumptions**:
after `fill`, grep each resolved ticket for the literal string `PENDING-COMMIT`;
if it is still present, say so and exit non-zero. A literal substring search
cannot be defeated by line wrapping, indentation or wording, and it is precisely
the independent instrument the `sync.sh` comment argues for.

Widening `PENDING_RE` to tolerate newlines is worth doing as well, but on its
own it only moves the boundary — the next unanticipated spelling is silent
again.

## Gate

Track T's own, plus a fixture with a wrapped citation that must fail `check`
before the fix and pass after. Test the tooling against a scratch bare repo
rather than a long run.

---

## FIXED 2026-08-30 — `verify_citations_landed` in `tools/sync.sh`

Built as sketched: a **second, dumber look that shares nothing with the regex**.
`grep -F`, after the fill, over the ticket files this run's commits touched.
`PENDING_RE` was **not** widened — a wider pattern only moves the boundary, and
the next unanticipated spelling is silent again.

### Scope is the whole design, and it is measurable

Run over the tree, a literal search fires on **9 files right now**, every one of
them prose *about* the placeholder — including this ticket, three tickets from
tonight's PENDING-COMMIT triage, and a 5000-line index. That is the false-positive
set two lanes spent an evening on, and putting an exit code behind it is how a
guard earns the habit of being scrolled past.

So the guard reads `manifest_tickets` — captured beside the subject manifest,
before the first rebase, with the same load-bearing `devdocs/progress/*/*.md`
glob `fill_pending_commits` depends on to keep `README.md` and the generated
boards out of reach. It fires **once**, on the sync that resolved the ticket,
and never again.

### Two conditions, deliberately not merged

| | | |
| --- | --- | --- |
| `pending` **named** the file and the literal survived | the **fill** is broken | **exit 1** |
| `pending` never named it | the regex is blind, *or* the line is prose | **warn, print the line, exit 0** |

The second never exits non-zero, and that is not timidity: **the push already
succeeded.** Reporting a healthy push as a failure is this file's own recorded
failure mode wearing the other hat. The defect here is *silence*, and a line
that names the file ends it.

Printing the offending line is what makes the prose case tolerable: one glance
settles prose-versus-real, which is a better answer than any pattern I could
write to guess it. **This ticket's own resolution demonstrates it** — the commit
moves a file that quotes the placeholder five times, so the sync that lands this
fix reports itself. Working as designed, and a nice thing to see once.

### On the doctrine, because this cuts against it

`normalise-dont-special-case` is right and the 2026-08-29 consolidation was
right. But it is worth stating what it cost: back then, the fill was sed literals
covering fewer spellings than `PENDING_RE`, so `check` counted what fill could
not fill, and **the mismatched numbers were the alarm**. Aligning them retired a
differential test that had been running free on every input. **Two divergent
implementations of one predicate are an oracle; consolidating them deletes it,
and nothing announces that.** This guard is the deliberate replacement — chosen
to be *independent*, not adjacent, because a better version of the same idea
inherits the same blind spot.

### Guard

`tools/sync_citation_guard_devtest.py` — **19 guards, 0 FAIL**, lifting
`verify_citations_landed` verbatim out of `sync.sh` rather than reimplementing
it. Section 1 pins the defect itself against the live `progress.PENDING_RE`: it
sees the flat citation, is **blind to the same citation wrapped**, and is blind
to prose — the last deliberately, and it must stay that way.

### Not done

- **`PENDING_RE` is unchanged**, so a wrapped citation is still not auto-filled.
  It is now *reported*, with the fix named in the message (unwrap it onto one
  line and re-run sync). Widening was declined on the reasoning above.
- No live stuck citation was found in the tree: all 9 current occurrences are
  prose, so frankC's own was already unwrapped by hand.

## Log
- 2026-08-30 — resolved, commit ad4db86ed.

### Correction, same night: the first cut failed on its own commit

The guard shipped and immediately cried **FILL FAILED** at a successful fill —
on the very push that introduced it.

Condition (a) was written as *"`pending` named this file **before** the fill, and
the literal is present **now**"*. A ticket that carried a real placeholder **and
quotes the placeholder in its write-up** satisfies both while being entirely
healthy: the citation filled, the prose stayed. This ticket quotes it five times,
so it was the first file the guard ever looked at and the first thing it got
wrong.

Fixed by asking `progress.py pending` **again, after the fill** — which is the
only honest form of "still owed". Before-state plus present-state is not the same
question, and the difference only shows on a file that has both.

**Nothing short of running it would have found this.** Every fixture in the
devtest had a real placeholder *or* prose, never both, so 19 guards passed on a
broken condition. Section 5 is now exactly that fixture, and it is the guard that
would have caught it.

That is the night's shape once more, one turn further in: I built an independent
oracle *because* aligned implementations stop disagreeing — and then wrote its
first condition against state I already had rather than the state it was asking
about. The guard was right to exist and wrong on its first input, and it is the
guard itself that reported it.

### Calibration fix, same night: it fired on every coordinator push

Reported by frank-coordinator. `feature-a-a-refusal-is-a-claim-with-a-date-on-it`
is the family index — a document *about* citations — so it contains narrative
like *"7 PENDING-COMMIT tickets, 2 false positives"*. The coordinator touches it
on most pushes, the guard read those lines as wrapped citations, and the
unwrap-it advice arrived every time and was never actionable.

**Mention versus use**, one level below the `regression-`/`decide-`/`grant-`
exclusion in the nudge. Two changes, and the first is the real one:

1. **Two questions, two candidate sets.** The first cut walked
   `manifest_tickets` — every ticket the push *touched* — for both conditions.
   Now (a) *is the fill broken?* asks `pending`, whose answer is authoritative and
   cannot contain prose, intersected with this push; and (b) *is a placeholder
   unseen?* looks only at tickets this push **resolved**. A wrapped citation can
   only be written by the resolve that moved the ticket, so nothing else is a
   candidate — and a document that merely discusses the mechanism is never
   resolved by a push.
2. **Bare occurrences only.** A real citation is bare; a document quoting the
   placeholder writes `` `PENDING-COMMIT` `` or **PENDING-COMMIT**. This removes
   the one false positive the scope split cannot reach: a resolved ticket whose
   own subject is this machinery.

Not a filename suppression list, on the coordinator's reasoning and mine: it
would decay the moment a second such document exists, and the family index will
not be the last document that discusses the mechanism it lives under.

Guard: 39 guards, 0 FAIL. Section 9 is the family index itself; 9a is the
backtick rule, with a bare wrapped citation beside it proving frankC's original
shape still reports.
