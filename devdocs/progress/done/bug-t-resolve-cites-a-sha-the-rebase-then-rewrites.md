---
summary: "The documented loop is commit -> resolve <slug> <sha> -> sync.sh, but sync.sh REBASES, so the sha written into the ticket no longer exists on origin. Four tickets in one session cited commits nobody else can look up."
type: bug
track: T
prio: 60
status: done
owner: claude@xeon
---

# `resolve <slug> <commit>` cites a sha that `sync.sh` then rewrites

- **Type:** bug (Track T — board tooling / the landing loop)
- **Opened:** 2026-08-02 by `claude@xeon`, after doing it four times in one
  session and catching it only on a final audit.

## The sequence, all of it documented practice

```sh
git commit                       # -> 688a174aa
tools/progress.sh resolve bug-t-bench-... 688a174aa   # writes that sha into the ticket
tools/sync.sh                    # pull --rebase + push  -> the commit is now 7225fb647
```

`sync.sh` rebases onto whatever origin gained meanwhile — and on this box that
is constant, because the watcher daemon publishes tstate commits every few
minutes. Rebasing rewrites every local commit, so the sha the ticket cites has
**no object on origin at all**. It survives only in the author's local reflog,
which is exactly the place the other box cannot look.

Measured this session — all four resolved tickets cited dead shas:

| cited | actually landed as |
|---|---|
| `12f1cd965` | `1dd53a8ec` |
| `03b90a755` | `1091a57d9` |
| `ef2005e8e` | `1f015d684` |
| `688a174aa` | `7225fb647` |

Also caught: a provenance marker written INTO `tstate/bench.tsv` naming the
commit that changed the measurement basis. That one would have been the worst
of the four — a data file telling a future reader to look up a commit that
does not exist.

## Why it bites here specifically and not everywhere

A repo where you push before anything else lands rarely rebases, so the naive
loop works. This fleet has a daemon committing to the same branch continuously,
so **a rebase is the norm, not the exception**. The tooling's own instructions
(`CLAUDE.md`: "resolve <slug> <commit>", `two-box-protocol.md`: "use sync.sh,
not git pull --rebase") compose into the bug.

## Fix directions (pick one; 2 is the least clever)

1. **Resolve AFTER the push.** Reorder the documented loop: commit, sync, then
   `resolve` with the landed sha, then a second tiny commit. Costs an extra
   commit per ticket and is easy to forget — the ordering is the whole fix, and
   nothing enforces it.
2. **Let `resolve` take no sha and fill it in at push time.** `sync.sh` already
   owns the push; after a successful push it can rewrite any
   `PENDING-COMMIT` placeholder in the tickets it is pushing to the sha they
   actually landed as. Deterministic, no ordering discipline required.
3. **`sync.sh` post-rebase fixup:** map pre-rebase to post-rebase shas (the
   rebase knows both) and rewrite citations in the commits being pushed.
   Most general, most machinery; a plain `git rebase` does not hand you the
   mapping without `--exec` or a rewritten-list hook.
4. **Cite nothing.** Drop shas from resolve lines entirely and rely on
   `git log -S<slug>`. Loses the direct link; `progress.sh check`'s
   WARN-NO-COMMIT rule exists precisely because that link is worth having.

Recommendation: **2**, with `check` growing a rule that flags a `done/` ticket
citing a sha absent from `origin/master` — the audit that caught this by hand,
made cheap. That rule is worth having regardless of which fix lands, because it
also catches a citation to a commit that was later reverted or dropped.

## Already done

The four citations above and the `bench.tsv` marker were rewritten to their
landed shas by hand. This ticket is about the loop that produced them.

## Log
- 2026-08-03 — resolved, commit PENDING-COMMIT.
