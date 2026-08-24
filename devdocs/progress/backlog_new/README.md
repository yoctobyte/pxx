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
- **Not ranked.** `tools/progress.sh ready`/`next` scan `urgent`, `working`,
  `unfinished` and `backlog` only, so nothing here is dispatched automatically —
  the same arrangement as `float/` and `experimental/`. It is picked up
  deliberately, or promoted into `backlog/` when someone decides it belongs in
  the ranked queue.
- **`urgent/` still exists and still means urgent.** This folder is the default
  destination, not the only one: something that must be worked *now* goes to
  `urgent/` as before.
- Resolving works exactly as it always did — `tools/progress.sh resolve <slug>`
  moves it to `done/`, no sha.
