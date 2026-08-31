---
summary: "twatch's auto-filed note tells the reader 'this commit CANNOT be the cause ... look at flakiness or box load' whenever a $(PXX_STABLE)-gated job goes red. The deduction is right and the conclusion is wrong: unchanged stable bytes rule out the COMMIT, not the PINNED BINARY, which is stale relative to any compiler fix landed since the last pin. That third branch is missing and it is the common case — the watcher re-files the same already-fixed finding every sweep until the pin moves."
track: T
prio: 35
type: chore
status: backlog
owner: unassigned
blocked-by: []
---

# A `$(PXX_STABLE)`-gated red should name pin lag before flakiness

Filed 2026-08-29 by `frankB` (Track B) from
[[regression-lib-test-lib-synapse-2]], which was auto-filed **ten minutes after
the bug it reports had been fixed in master** and cost a triage cycle before
that was visible.

## The note as it stands

Every auto-filed ticket for a job that builds with `$(PXX_STABLE)` carries:

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`,
> and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled
> it are unchanged. Look at flakiness or box load, not at the named sha; the
> bisect is unsound here and has been skipped.

Everything up to the last sentence is correct and genuinely useful — suppressing
an unsound bisect is the right call. The last sentence is the problem: it offers
**two** branches where the deduction has **three**.

| stable bytes unchanged ⇒ | |
| --- | --- |
| not the named commit | correct, and worth saying |
| flakiness or box load | the only alternative currently offered |
| **the pin is stale relative to a fix already in master** | **missing — and it is the common case** |

"The bytes that compiled it are unchanged" rules out the *commit*. It says
nothing about whether those bytes are **correct**, and a pinned binary is by
construction as old as the last pin. Every compiler fix that lands between two
pins produces exactly this: a `$(PXX_STABLE)` job that stays red at HEAD shas
for a defect HEAD no longer has.

## Why it matters more than a wording nit

**It re-files.** In the pin-lag window the watcher raises the same finding on
every sweep, each against a fresh innocent sha — `regression-lib-test-lib-synapse`
then `-2`, with `-3` due on the next sweep had the pin not moved. Each arrives
labelled "look at flakiness or box load", so each costs a triage that ends in
the same place.

**And a named cause stops the next reader looking.** "Flakiness or box load" is
unfalsifiable enough to absorb a real finding: it explains any red, needs no
evidence, and closes the question. The one thing it reliably prevents is
someone checking `pinned`'s age.

## Suggested change — cheap, and it is a template edit

When a job's build uses `$(PXX_STABLE)`, add a branch before the flakiness one:

> **Check the pin first.** This job compiles with `stable_linux_amd64/default/pinned`
> (currently vNNN, blessed at `<sha>`, N commits behind origin/master). If a
> compiler fix landed after that pin, this job cannot see it and will stay red
> until the pin moves. Confirm with: build the failing source with
> `compiler/pascal26` at HEAD — if HEAD compiles it and `pinned` does not, this
> is pin lag, not a regression. Only then consider flakiness or box load.

The version and blessed-sha are already known to the watcher, so the note can
state the actual lag rather than the general caution — "**v390, 3h and 340
commits behind**" is the whole triage in one line, and it is the line that was
missing here.

## Verified instance

`regression-lib-test-lib-synapse-2`: fix `614ec6017` landed 18:47Z, ticket filed
18:57Z, job red under v390 the whole time. Same command, same corpus, same box:
**red at v390, green at v391**. The reader was told to look at box load.
