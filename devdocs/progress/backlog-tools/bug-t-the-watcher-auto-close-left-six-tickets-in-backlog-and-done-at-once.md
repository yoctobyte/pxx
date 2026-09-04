---
slug: bug-t-the-watcher-auto-close-left-six-tickets-in-backlog-and-done-at-once
track: T
type: bug
prio: 45
status: open
created: 2026-09-04
found-by: frankC
blocked-by: []
summary: "twatch's auto-close wrote six tickets into `done/` on 2026-09-03 (`3dcfe8404`) WITHOUT removing their `backlog/` copies, so six resolved regressions kept ranking as open at prio 70 until 2026-09-04. The close commit is `6 files changed, 355 insertions(+)` and ZERO deletions, while the code at `twatch.py:5002` plainly does `os.unlink(src)` and appends BOTH paths to what it publishes. **The obvious explanation is EXCLUDED by measurement**: publish()'s own sequence — `git checkout <branch>`, `git add -- <paths>`, `git commit -- <paths>` — records a deletion correctly when the clone is already on the branch (reproduced in a scratch repo: `b.md | 1 -`). So the fault is UPSTREAM of publish, not in it: either `src` did not name the backlog copy in that clone, or that clone did not have the filing commit `59344428a` (same host, 2h47m earlier) when it built `paths`. The duplicates themselves are cleared; this is the mechanism, unfixed, and it will recur on the next auto-close."
---

# What was measured

`tools/progress.sh check` has a DUPLICATE-SLUG aperture and was already
reporting all six. That is the good news: the bookkeeping tool sees it. Nothing
acts on it, and the six sat at the top of a prio-70 queue for a day.

```
59344428a  2026-09-03 17:59:39Z  filed  6 files -> backlog/, 337 insertions
3dcfe8404  2026-09-03 20:46:30Z  closed 6 files -> done/,   355 insertions, 0 deletions
```

Each of the twelve paths is touched by exactly one commit in the whole history,
so nothing re-created the backlog copies afterwards: the close simply never
recorded their removal.

`done/` is a strict superset of `backlog/` for all six — zero backlog-only lines,
three added lines each (the auto-close `## Log` entry). Verified with `diff`
before deleting, as `check`'s own advice requires; the backlog copies are now
`git rm`'d and `check` reports zero DUPLICATE-SLUG.

# What was EXCLUDED, so the next person does not re-derive it

The natural reading is that `publish()` drops deletions, because it commits with
an explicit pathspec and does a `git checkout` first. **That is wrong.** In a
scratch repo, with a file added in a later commit than HEAD~1, the exact
sequence from `twatch.py:789-795`:

```
rm b.md
git checkout --quiet master      # b.md stays deleted
git add -- b.md c.md
git commit -m close -- b.md c.md # -> b.md | 1 -   c.md | 1 +
```

records the deletion. So `publish()` is not the bug and reading it again is
wasted time.

# Where to look instead

Both remaining candidates are about the state `src` was computed from, not
about git:

1. `src` did not point at `devdocs/progress/backlog/<slug>.md` in that clone —
   the body was read from somewhere (or from the tstate record), and `unlink`
   removed a path that was not the one on origin.
2. The closing clone had not pulled `59344428a`. It ran 2h47m later on the same
   host, but the watcher works in a detached clone with its own fetch cadence,
   and a clone without the filing commit has no backlog copy to unlink — the
   `unlink` would then raise `FileNotFoundError` and abort the slug, or be
   guarded and silently skipped.

Candidate 2 is checkable from the daemon's own logs on seven
(`twatch: auto-closed N stub ticket(s)` was printed for all six, so no exception
escaped) and predicts a guarded skip rather than a raise.

# Why it is prio 45 and not higher

It cannot make a red look green: the `done/` copy is written correctly and
carries its evidence, so the CLOSE is real. The cost is that a resolved
regression keeps a live claim at prio 70 in whatever lane the track guess sent
it to — six of them, for a day, at the top of several queues. That is queue
pollution and wasted claims, not a wrong verdict.

Filed rather than fixed: the daemon runs on seven, this seat cannot reproduce
the clone state that produced it, and a change to the close path that is not
verified against a real auto-close is how the second copy of this bug gets
written. `check`'s aperture already catches the residue, which is the safety net
until then.
