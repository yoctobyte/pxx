# `backlog_new/` — everything filed from 2026-08-24 onward

**Rule (user, 2026-08-24): any NEW ticket goes here. Important or not.**

> *"our tickets go from gross compiler issues to nitpicking details, and we have
> a hard time sorting them out since they are all called 'bug'. so, from here on,
> any new tickets filed are fair game, just they go into `backlog_new`."*

## What this folder is FOR

Filing is now **free**. The old `backlog/` grew to a size where the cost of a
ticket was the cost of *placing* it — is this urgent, is it really a bug, does it
deserve a prio — and that friction is paid on every finding, including the small
ones that are cheap to fix and expensive to rediscover. This folder removes the
friction: **file it, don't sort it.**

The sorting axis is **date**, not judgement. Everything here was filed after
2026-08-24, so "what has come in recently" is answerable by listing the folder,
which is precisely what `backlog/` can no longer answer.

## Rules

- **New ticket → here.** A gross miscompile and a cosmetic nitpick file the same
  way. Do not pre-triage into `backlog/`.
- Frontmatter is unchanged — `track:`, `prio:`, `type:`, `summary:`, `blocked-by:`.
  Set `prio:` if you have an opinion; leave it at the default if you do not.
- **Ranked, exactly like `backlog/`.** `Board.RANKED_STATUSES` is
  `urgent`/`backlog`/`backlog_new`/`unfinished`, asserted by
  `tools/progress_ranked_statuses_devtest.py`, so `ready`/`next` dispatch from
  here like anywhere else. The split is a FILING convenience — sort by date
  instead of by a judgement call at filing time — **not** a parking lot.

  > This bullet used to say the opposite ("Not ranked... nothing here is
  > dispatched automatically... the same arrangement as `float/`"). That was
  > true of the lane as first conceived and false of the lane as built; it was
  > ranked from the start in code. Anyone who read this README to decide where
  > to file was told their ticket would sit undispatched when it would not.
  > `float/` and `experimental/` ARE unranked — those are the real parking lots.
- **`urgent/` still exists and still means urgent.** This folder is the default
  destination, not the only one: something that must be worked *now* goes to
  `urgent/` as before.
- Resolving works exactly as it always did — `tools/progress.sh resolve <slug>`
  moves it to `done/`, no sha.

## Drained 2026-08-27

All 24 tickets then in this folder were moved to `backlog/` at the owner's
request; `README.md` stayed. Nothing was lost in the move — the lane is ranked
identically, so no ticket changed dispatch position, and `status:` frontmatter
that said `backlog_new` was rewritten to `backlog` so no ticket claims a folder
it is not in. Filing dates remain recoverable from git.

The lane itself is **not retired**: the rule above still stands and new tickets
still land here. Draining it periodically into `backlog/` is what keeps "what
came in recently" answerable by listing the folder, which is the whole reason
it exists.
