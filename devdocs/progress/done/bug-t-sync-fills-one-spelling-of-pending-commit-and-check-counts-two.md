---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`check` has reported the same 17 PENDING-COMMIT tickets for weeks and `sync.sh` reports nothing to fill, because they anchor on DIFFERENT spellings of the field: check substring-matches the placeholder anywhere, sync greps only the Log form `commit 4b8864737` (space), and all 15 live instances are the frontmatter form `commit: PENDING-COMMIT` (colon). Both tools are behaving correctly and the count can never go down."
status: done
---

# `sync.sh` fills one spelling of PENDING-COMMIT; `check` counts two

## Symptom

`tools/progress.sh check` reports, indefinitely:

```
PENDING-COMMIT: 17 resolved ticket(s) await their landed sha — run: tools/sync.sh
```

Running `tools/sync.sh` does exactly what it is told, pushes, and fills nothing.
Re-running `check` reports 17 again. Neither tool prints an error — this is why it
has survived: each half looks correct in isolation, and the instruction that check
prints is genuinely the right instruction, it just has no effect.

Noticed 2026-08-18 by frank3-fc, which ran `check` after an unrelated fix, saw the
count unchanged across a `sync.sh` that had just reported success, and escalated it
rather than assuming it was leftovers.

## Root cause — two spellings of one field

There are two places a resolved ticket can cite its commit, and the two tools do not
agree on which is the citation:

| | writes | reads |
| --- | --- | --- |
| `progress.py resolve` | a **Log line**: `- <date> — resolved, commit 4b8864737.` | — |
| a worker, by hand | **frontmatter**: `commit: PENDING-COMMIT` | — |
| `progress.py check` (:961) | — | `if PENDING_COMMIT in t.text` — a bare substring test, so it counts **both** |
| `sync.sh` (:122) | — | `git grep -l -- "commit 4b8864737"` — the space form **only** |

Measured on master at `67a1ca4e1`:

```
colon form (`commit: PENDING-COMMIT`):  15 files
space form (`commit 4b8864737`):    0 files
```

So `sync.sh`'s `fill_pending_commits()` is effectively dead code. Its grep cannot
match a colon, every live placeholder has one, and it returns early on an empty file
list — silently, since an empty list is the normal healthy case.

The anchoring is deliberate and documented; the comment at `sync.sh:136` says
"Anchored to the citation `resolve` writes", and that was true when written. What
drifted is that tickets acquired a frontmatter `commit:` field that `resolve` does
not write and `sync.sh` was never taught about, while `check` counts by substring and
so silently picked up the new form for free.

## The trap in the obvious fix

**Do not simply widen the grep to match both forms.** The two placeholders are
introduced by different commits and only one of them is the sha anyone wants:

- The **Log** form is written BY `resolve`, so `git log -1 -S` finds the resolve
  commit — which is the landing commit, which is the point.
- The **frontmatter** form is hand-written by a worker, and where it lands is
  whatever commit that worker happened to include it in.

Spot-checked `bug-nilpy-hasattr-does-not-see-a-property.md`: `-S` returns `d9d3f39f1`,
which IS its fix commit — correct, but only because that worker wrote the frontmatter
line in the same commit as the fix. Nothing enforces that. A placeholder added when
the ticket was FILED would resolve to the filing commit and cite a sha that has
nothing to do with the fix, and it would look completely plausible in the board.

This is the failure mode already on record as
`bug-t-resolve-cites-a-sha-the-rebase-then-rewrites` and in the standing rule that sha
citations must never be auto-repaired by matching against `git log` — roughly 82% of
them look fixable that way and matching is the wrong operation. A filler that is
right by luck on today's 15 files is not a fix.

## What to decide

Pick ONE spelling as the citation and make both tools agree on it. Two candidates:

1. **Frontmatter wins.** `resolve` writes `commit:` in frontmatter instead of a Log
   line; `sync.sh` fills that field; `check` keeps its substring test. Frontmatter is
   already what the board parses, and it is where workers' instincts put it — the
   drift is evidence of that.
2. **Log wins.** `check` narrows to the same anchored pattern `sync.sh` uses, and the
   15 frontmatter instances are migrated once, by hand, each verified against the
   commit that actually carries its fix.

Either way `check` and `sync.sh` must read the SAME pattern, and it should be a shared
constant rather than a literal repeated in a Python file and a shell script — that
duplication is the actual defect and is what let the two drift apart unnoticed.

Whichever is chosen, the 15 existing files need their shas established by looking at
what the ticket says it fixed, not by a bulk `-S` sweep.

## Gate

Track T's own tooling gate for a tooling change, plus: a scratch bare repo exercising
both spellings — `tools/sync_pending_commit_devtest.py` already exists and covers the
space form, so extend it rather than writing a second harness. Confirm `check` reaches
0 on a repo where `sync.sh` has run, which is the property that was never true.

## Resolved 2026-08-19 by Track T (plexus-T)

**The decision the ticket asked for: neither spelling "wins" — both are
citations, and the duplication that let them drift is what gets removed.**

Option 1 (frontmatter wins) and option 2 (Log wins) both require migrating live
instances by hand, and both leave the same underlying defect in place: two
tools, each with its own copy of "what counts as an unfilled citation". The
ticket names that itself — *"that duplication is the actual defect and is what
let the two drift apart unnoticed"* — so the fix is to delete the duplication
rather than to pick a winner and re-create it.

- `progress.py` owns the definition: `PENDING_RE`, anchored to **line start**,
  matching both `commit: PENDING-COMMIT` (frontmatter, hand-written) and
  `- <date> — resolved, commit PENDING-COMMIT.` (the Log line `resolve` writes).
- New `progress.sh pending` prints `<path>\t<sha>` per ticket owing a citation.
- `sync.sh` consumes that instead of carrying its own grep. One implementation,
  so drift is not possible rather than merely unlikely.
- `check` counts what `sync` can fill — same pattern, same buckets.

**Line-start anchoring is load-bearing and this ticket proved it.** The first
draft used `\bcommit:?\s+PENDING-COMMIT`, which matched **this ticket's own
table**, so the report about the bug was itself counted as an instance of the
bug. Prose quotes the placeholder mid-line, inside backticks or a table cell;
citations begin their line.

**Open buckets are excluded.** A placeholder in `backlog/` or `working/` is
correct — the ticket has not landed and there is no commit to cite. `check` was
counting those, `sync` could never fill them, and the difference was permanent.

### A third defect, not in the ticket, found while fixing it

`sync.sh` located the sha with `git log -1 --format=%h -S PENDING-COMMIT -- <f>`,
under the comment *"the commit that INTRODUCED the placeholder is the resolve
commit"*. **`-S` finds commits where the occurrence COUNT CHANGED — in either
direction.** On any ticket a previous sync already filled, the most recent such
change is the **fill**, so the ticket would cite the tool that wrote the
citation. Measured on the live repo, 4 sampled tickets:

```
bug-n-a-keyword-argument-through-a-callable-value-is-undefined
  -S              -> 5dfc7c945 docs(progress): record the shas the resolves landed as
  first-in-done   -> 9e711a681 feat(nilpy): a keyword argument through a callable value binds ...
bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view
  -S              -> 518d7681e docs(progress): record the shas ...
  first-in-done   -> 810f219c3 fix(N): a user class's keys/items/values is no longer hijacked ...
```

3 of 4 resolved to a `docs(progress)` fill commit. The replacement,
`resolve_commit()`, takes the **first commit to touch the ticket at its resolved
path** — the resolve itself. That is a structural fact about the file's history,
not a match against its content, which is the distinction that keeps it clear of
[[bug-t-resolve-cites-a-sha-the-rebase-then-rewrites]]. On the same four it
recovered the actual fix commit every time.

### NOT DONE, deliberately: the 25 existing tickets are not filled

`check` and `pending` now agree at **25**, and the fill is safe to run — but
running it is a separate, deliberate act and is left to whoever is accounting
for those tickets. Preview without changing anything:

```sh
tools/progress.sh pending          # <path>\t<sha>, inspect before filling
```

### Gate

`tools/sync_pending_commit_devtest.py` extended rather than replaced, as the
ticket's Gate section asks — 6 existing cases still green, 4 added, **all four
verified to FAIL on the unfixed tools**:

| case | on the old code |
| --- | --- |
| the frontmatter spelling is filled | placeholder survived onto origin |
| `check` and `pending` are one set | check counted 1, pending listed 0 |
| an open bucket's placeholder is left alone | check counted it |
| a refill cites the resolve, not the previous fill | cited two shas, one being the fill |

It runs in `make tools-devtest` (limited + full) as of `a1fd5715e`, so this
cannot silently rot the way the five in that ticket did.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
