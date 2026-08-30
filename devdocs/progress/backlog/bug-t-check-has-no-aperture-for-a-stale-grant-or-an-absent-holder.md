---
slug: bug-t-check-has-no-aperture-for-a-stale-grant-or-an-absent-holder
title: "check has no aperture for a stale grant or an absent grant holder — three instances in one afternoon"
track: T
prio: 45
type: bug
status: open
created: 2026-08-30
found-by: frank-coordinator
summary: "A grant ticket is a file lock the ranker cannot see. Filing one makes it ENUMERABLE but not CURRENT, and nothing notices when its holder's session ends. Asks for two apertures in progress.py check: GRANT-STALE (the grant's parent work is resolved) and GRANT-NO-HOLDER (owner: names no live session). Three measured instances on 2026-08-30, two of which produced a real dispatch error."
---

# The gap

`devdocs/progress/backlog/grant-*.md` records a coordinator's authorisation for one agent to
edit a file another lane owns. It exists because **a grant is a lock the ranker cannot see**
(`bug-t-a-grant-is-a-lock-the-ranker-cannot-see`) — `ready`/`next` will happily offer a
ticket whose file is granted away.

Filing the grant fixed half the problem. It made grants **enumerable**. It did not make them
**current**, and it does not notice when the holder stops existing.

`check` has `STALE-PARK` for a prose park condition whose blocker has closed. **There is no
equivalent for a grant**, and a grant is strictly more dangerous than a park: a stale park
delays one ticket, a stale grant misdirects a dispatch.

## Three instances, 2026-08-30, all within about two hours

**1. STALE, wide grant missed by a release sweep.** The coordinator released two narrow
`ir_codegen.inc` grants to frankS by recalling which grants it had given, and missed
`grant-ir-codegen-call0-cleanup-frame-to-franks` — the **whole-file** one, on the file frankA
was in at that moment. Caught by frankS, whose diagnosis is the ticket's thesis:

> A filed grant can read as covered too, if the release sweep works from the wrong list.

**2. STALE CONTENT contradicting the live dispatch.**
`grant-lexer-writediagsourcefile-to-frankc-and-the-ir-codegen-dual-occupancy`'s section 2
recorded frankS holding `EmitParamSpillsForTarget`'s xtensa arm and frankA in `EmitSyscall`.
**Both rows were false**, and the filed version said the function frankA was working in
belonged to frankS. Not a collision — frankS's side was stale — but *the board contradicted
the dispatch, and the board is what anyone else would check.* Anyone reconciling the two
would have concluded frankA was trespassing.

That grant also carried a **lapse condition** ("the rotation stays inside `EmitSyscall` with
no caller changes; if that stops being true the grant lapses") which had silently expired.

**3. NO HOLDER.** `grant-elf-writer-and-object-writers-to-b4` named `owner:
frank-optimize-b4`, **a session that is not running**. A lock with no holder is worse than no
lock: it reserves files against agents who would otherwise be dispatched to them, invisibly.
It also showed `defs.inc` with two live holders (harmless in fact — type kinds are not ELF
constants — but unreadable as such from the board).

## The ask

Two apertures in `tools/progress.py check`:

- **`GRANT-STALE`** — a `type: grant` ticket in a ranked folder whose parent/discharging
  ticket is in `done/` or `rejected/`, or whose stated lapse condition names a resolved
  ticket. Same shape as `STALE-PARK`, reading grant frontmatter instead of park prose.
- **`GRANT-NO-HOLDER`** — a grant whose `owner:` matches no live session. This one needs a
  liveness source; if `check` cannot have one, degrade to **age**: a grant older than N hours
  with no commit touching its granted files is a candidate. Better a weak heuristic that
  fires than an aperture that cannot exist.

Report as advisories, not failures. A legitimate long-held grant must not red the board.

## Warnings for whoever implements it

**Do not auto-close anything.** Releasing a lock and closing the work it covered are
**different acts**, and conflating them is how a half-done slice gets recorded as done. The
b4 case above was annotated as *lapsed by absence*, explicitly not resolved, because nothing
established whether that slice had finished. An aperture that resolves stale grants would
have silently claimed it did.

**Do not key the check on the marker.** `_NODISPATCH_RE` (`tools/progress.py:231`) matches
`NOT DISPATCHABLE|do not claim` in ticket **text**, which is why a coordinator note quoting
that phrase once suppressed a ticket it was describing. Key on `type: grant` in frontmatter
— *"declare a track in frontmatter; that is what the ranker reads"* applies here too.

**Expect false positives and make them one-read dismissible.** `STALE-PARK` matches slugs,
not questions, and produced a false positive the same day that took frankC one read to
dismiss. That is the healthy failure mode; the alternative misses the real ones.

## Why this is worth p45 rather than tooling polish

The coordinator role has no other index. `working/` is a live lock the ranker respects;
grants are a live lock **only the coordinator remembers**, and remembering is what failed
three times in one afternoon. Recall does not degrade toward obviously-missing — it degrades
toward **plausibly-complete**, which is why being careful reproduces the failure rather than
preventing it.

The interim procedure is `ls devdocs/progress/backlog/grant-*` before
saying any file is free. It works and it is one second. It is also exactly the kind of thing
a human coordinator cannot hold across a day, which is why it belongs in `check`.
