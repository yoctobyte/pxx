---
slug: feature-t-commit-trailer-hook
track: T
prio: 60
type: feature
blocked-by: []
summary: "Two thirds of agent commits (840 of 1262 in one night) carry no Claude-Session trailer, so a collision cannot be attributed to the sessions involved. CLAUDE_CODE_SESSION_ID is in every agent's environment; a prepare-commit-msg hook can append the trailer unconditionally instead of relying on the voluntary act that is already failing 2 times in 3."
status: open
---

# T: append the session trailer from a hook, not from memory

Decided in `decided/decide-the-ticket-lock-is-too-heavy-for-a-per-minute-commit-loop`
(owner, 2026-08-30). That ticket rejected file locks and lock-dropping; this is
the one piece it accepted, and it is tooling, so it is T's.

## The measurement

Over `origin/master` 2026-08-29 18:00 -> 2026-08-30 09:00, excluding watcher
commits (`tstate*` — a daemon with no session, correctly untrailed):

```
agent commits   1262
with trailer     422  (33%)
missing          840
```

The ticket that prompted this cited 219/607; the true rate is worse. The cost is
not hypothetical: frankA hit a near-miss in `ir_codegen.inc` and **could not
identify the two sessions it would most have collided with**, with the whole log
in front of it.

## Why a hook works where instruction does not

`CLAUDE_CODE_SESSION_ID` is set in every agent's environment (verified
2026-08-30). A `prepare-commit-msg` hook reads it and appends the trailer
unconditionally, so the population that currently skips it — hurried commits,
scripted commits, mid-refactor banks — is exactly the population it covers.

The repo already ships a tracked hook (`.claude/hooks/no-full-suite.sh`, wired
in `.claude/settings.json`), so the pattern and the install path exist.

## Requirements

- Append `Claude-Session:` only when absent — never duplicate an existing one,
  and never rewrite a trailer a session wrote itself.
- **No-op when the variable is unset.** The watcher commits from a daemon with
  no session; those must stay untrailed rather than gain a wrong one, and
  `tools/twatch.py` must not start failing commits because a hook errored.
- Must not interfere with `git rebase` / `--amend`, which this repo does on
  nearly every sync — the hook sees those too.
- Survives a fresh clone: `git clone` does not install `.git/hooks`, so the
  install must ride on something a new box already runs (`trackt setup`, or a
  tracked `core.hooksPath`). A hook only present on plexus reproduces the same
  gap on every new watcher box.

## Gate

Track T's own tooling gate as defined in `devdocs/dev/track-t.md` (T holds the
`PXX_TRACK=T` escape for it), plus the functional check that actually settles
this one: make a commit with `CLAUDE_CODE_SESSION_ID` set and one with it unset,
and confirm the trailer appears in the first and not the second. Also confirm a
rebase of a trailered commit does not duplicate it.

## Verify after landing

Re-run the attribution count over a later window. The number to move is
**33% -> ~100% of agent commits**; watcher commits should stay at 0%.
