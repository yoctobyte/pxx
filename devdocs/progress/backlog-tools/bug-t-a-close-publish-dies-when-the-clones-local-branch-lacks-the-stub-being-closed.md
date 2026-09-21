---
slug: bug-t-a-close-publish-dies-when-the-clones-local-branch-lacks-the-stub-being-closed
title: "close_stub_tickets raises when the clone's local branch does not carry the stub it is closing"
track: T
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-21
summary: "MEASURED 2026-09-21 in a scratch clone, found while fixing the auto-close duplicate: if a stub was filed on origin AFTER this clone's last publish, the clone tests DETACHED at a sha that has the ticket, reads it, unlinks it — and then `Clone.publish()` checks out the local branch, which never had the file, so `git add -- <backlog path>` exits 128 with `fatal: pathspec ... did not match any files` and the RuntimeError aborts the whole close. Distinct from the duplicate bug (fixed at the sibling ticket): that one loses a deletion silently, this one is loud and takes the cycle's other closes with it. NOT reproduced in production and no evidence it has fired — a single live watcher host (borg) publishes often enough that its branch tracks origin closely, so the window needs a second filer. Repro is four commands in a scratch repo; it needs a decision about publish()'s contract rather than a local patch, which is why it is filed and not fixed."
---

# What was measured

Scratch bare repo, a clone, and a second clone standing in for another filing
host. Sequence, all of it production shape:

1. the other host files `backlog/<slug>.md` and pushes;
2. this clone fetches and checks out that sha **detached** — the stub is in
   the worktree, so `stub_backlog_path()` finds it and the body reads fine;
3. the close writes `done/<slug>.md` and unlinks the backlog copy;
4. `Clone.publish()` runs `git checkout --quiet master` — and this clone's
   `master` predates the filing commit, so the path is neither present nor
   tracked;
5. `git add -- devdocs/progress/backlog/<slug>.md devdocs/progress/done/<slug>.md`
   → `fatal: pathspec ... did not match any files`, exit 128.

`sh()` raises, and nothing between `close_stub_tickets` and the cycle catches
it, so every other close queued in the same call is lost too.

# Why it is prio 30 and not higher

It cannot produce a wrong verdict, and it is loud. It also needs a filer that
is not this host: `publish()` runs on essentially every cycle and leaves the
clone's branch at origin, so the window is small with one watcher. plexus and
seven are both RETIRED, so today there is exactly one. **Re-rank this up if a
second watcher host is enrolled** — the xeon enrolment plan would do it.

# Fix shape, and why it is not patched here

`git add` failing on a pathspec that matches nothing is the correct behaviour
of the instrument; what is wrong is that `publish()` is handed a path its
branch cannot know about. Candidates, none obviously right:

* have `publish()` drop paths that are neither present nor tracked, with a
  printed reason — cheap, but it makes a real staging bug silent, which is the
  thing `publish()`'s current shape is deliberately loud about;
* have `close_stub_tickets()` refuse a stub whose path is absent from the
  branch tip and say so — narrower, one extra git call per close;
* have the close pull before it decides, so the branch carries what it read.

That is a contract question about `publish()`, which every verdict goes
through. It wants deciding rather than guessing.

# Repro

`tools/twatch_close_stubs_devtest.py` case 8 covers the sibling (duplicate)
bug. This one is NOT guarded — a guard would have to assert a raise, and the
fix will change what happens instead, so the guard belongs with the fix.
