---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`check` has reported the same 17 PENDING-COMMIT tickets for weeks and `sync.sh` reports nothing to fill, because they anchor on DIFFERENT spellings of the field: check substring-matches the placeholder anywhere, sync greps only the Log form `commit 4b8864737` (space), and all 15 live instances are the frontmatter form `commit: PENDING-COMMIT` (colon). Both tools are behaving correctly and the count can never go down."
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
