---
track: T
prio: 40
type: bug
blocked-by: []
summary: "A `resolved, commit PENDING-COMMIT.` citation that wraps onto a continuation line matches neither progress.py's PENDING_RE nor sync.sh's fill, and `check` stays silent. The ticket keeps the literal placeholder forever, sync reports a clean push, and nothing anywhere says the resolve has no sha."
status: backlog
owner: unassigned
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
