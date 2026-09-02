---
track: T
prio: 20
type: refactor
status: rejected
owner: ""
blocked-by: []
summary: "NOT a present fault -- verified correct today. The automated pin path in tools/testmgr.py stages the stable tree with `git add -u <root>` plus an explicit `git add <root>/default/builtin`. The second call is what saves it, and it saves it by NAMING the one directory that has ever needed saving. `git add -u` stages tracked files only, so any FUTURE directory added under the stable root is silently left untracked in the pin commit, exactly as builtin/ was before that line existed. Correct by hardcoded path rather than by rule."
---

# The automated pin stages the stable tree by a hardcoded path, not by a rule

- **Filed:** 2026-08-30 by frankA (Track A), from the Makefile side of the same
  seam. **Track T's file — not edited.** `seven` runs T and decides this.
- **Nothing is broken today.** This is a latent version of a bug that has
  already fired once, filed so the next person does not re-derive that the
  current state is fine.

## Where

`tools/testmgr.py`, in the automated pin path:

```python
_git("add", "-u", STABLE_ROOT_REL)                    # tracked files only
_git("add", STABLE_DEFAULT_REL + "/builtin")          # this is what saves it
```

## Verified correct today, with its exact pair rather than by reading it

Plain `git add <dir>` stages additions *and* deletions inside that directory, so
`builtin/` is fully covered. Run against a freeze that adds a builtin unit,
drops a builtin unit, and adds a file in a **sibling** directory:

```
A  .../builtin/builtinentropy.pas     staged
D  .../builtin/goingaway.pas          staged
M  .../stable_pinned                  staged
?? .../newdir/added.txt               LEFT UNTRACKED
```

So the automated path was **never exposed** to
[[bug-a-a-pin-that-adds-a-builtin-unit-cannot-commit-it-with-git-add-u]], the
`make pin` bug fixed the same day. No fix is owed. The last row is the hazard.

## Why it is worth a ticket anyway

The protection is a **path**, not a rule. `builtin/` is covered because someone
hit that exact failure once and named that exact directory; nothing generalises
the lesson. A second directory under the stable root — a frozen `lib/` subset, a
target-specific tree, anything a future pin decides to snapshot — reproduces the
original bug identically, and inherits its worst property: **every check in the
chain passes and the artifact is still wrong**, because the files are on disk
and only a consumer of `stable_linux_amd64/` *alone* ever notices.

The timing is what makes it expensive. The fault appears at the moment someone
**adds a directory to the pin**, which is precisely the moment nobody is reading
the staging code — they are thinking about what to freeze, not about how it gets
committed.

## Suggested shape, T's call

`git add -A -- <stable root>` in place of the pair, which is what `make pin`
now does (`930c3ca69`) and what `make revert` has always done. If `-A` is too
broad for T's taste, `git add -- <stable root>` also stages additions and
deletions without the ignored-file semantics. Either replaces two calls with one
and removes the need for anyone to remember to add a third.

Checked before recommending it: `stable_linux_amd64/` currently has **zero**
untracked and **zero** ignored files, so `-A` there stages the pin's own output
and nothing else.

## Related

- `make pin`'s half of this: `bug-a-a-pin-that-adds-a-builtin-unit-cannot-commit-it-with-git-add-u` (fixed, `930c3ca69`)
- The other pin-path defect found the same day, same cause of a different kind —
  correct by convention rather than by construction:
  `bug-a-make-pin-overwrites-the-running-pinned-binary-in-place` (fixed, `9d8fbfb95`)

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
