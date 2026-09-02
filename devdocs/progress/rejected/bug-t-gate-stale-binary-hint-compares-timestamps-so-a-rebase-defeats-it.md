---
track: T
prio: 55
type: bug
status: rejected
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "gate.sh's stale_binary_hint() compares a COMMIT TIMESTAMP (git log -1 --format=%ct -- compiler/) against the binary's FILE MTIME. A `git pull --rebase` re-dates commits without changing content, so a binary genuinely built from exactly those sources is declared STALE. Observed by frankB: the note fired on a correct binary, a forced rebuild produced a byte-identical sha, and frankA reached the same bytes independently in a separate checkout. The defect is self-concealing — acting on the note produces a green and never reveals the note was wrong. The tree already has the right instrument: tools/compiler_srchash.sh, a content hash over the same file set."
---

# `stale_binary_hint()` compares timestamps, so a rebase defeats it

## The code

`tools/gate.sh:107`:

```sh
stale_binary_hint() {
  local newest binmt
  newest=$(git log -1 --format=%ct -- compiler/ 2>/dev/null) || return 0
  binmt=$(stat -c %Y compiler/pascal26 2>/dev/null) || return 0
  [ -n "$newest" ] && [ -n "$binmt" ] || return 0
  if [ "$binmt" -lt "$newest" ]; then
    echo "gate: NOTE compiler/pascal26 is OLDER than the last commit touching"
    ...
```

A **commit timestamp** against a **file mtime**. `git pull --rebase` rewrites
commits and gives them new committer dates while changing nothing about the
sources, so the binary that was correct a second ago becomes "older than the
last commit touching compiler/" and the gate advises a rebuild it does not need.

## Observed

frankB, wide tier at `3f9937e6c`: every step PASS except the self-host
fixedpoint, with the stale-binary NOTE attached. Their `tools/sync.sh` had run a
`pull --rebase` at 23:37:01, mid-step. Two independent checks that the binary was
in fact correct:

- re-running `tools/selfhost_fixedpoint.sh` standalone on a settled tree prints
  *"converged after 2 round(s) from pinned"* **and** *"agrees with
  compiler/pascal26"*, rc=0;
- frankA, in a **separate checkout**, removed the stamp to force a real rebuild
  and reached `d2b79a9ddb65` — byte-identical.

Two routes, same bytes. The binary was never stale.

## Why this is worse than a false positive

**It is self-concealing.** The note reached a useful conclusion — "do not
believe this FAIL" — from a false premise. Anyone who acts on it by rebuilding
and re-gating gets a green, concludes the note was right, and never learns the
premise was wrong. A wrong instrument that is *rewarded* for being wrong will
not be found by using it; it can only be found by reading it, which is what
happened here and only because frankB checked the binary two other ways first.

## The fix is already in the tree

`tools/compiler_srchash.sh` prints one hash over **every source the self-host
fixedpoint is a fixedpoint of** — per-file sha256 hashed as a sorted set, so it
covers names as well as contents, and `tools/selfhost_stamp_devtest.sh` asserts
its file list matches the Makefile's in both directions. It is immune to
rebases, cherry-picks, and mtime churn, because it hashes content.

`compiler/.pascal26.fixedpoint` already records a `srchash` line for exactly
this comparison. The staleness question is:

```sh
[ "$(tools/compiler_srchash.sh)" = "$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint)" ]
```

Content vs content. Note this is strictly *more* informative than the timestamp
test — it also catches a binary built from *different* sources that happen to be
newer, which the mtime comparison cannot see at all.

Keep the hint a **hint**: the comment above the function is right that gate.sh
must not rebuild before comparing, or it loses the anti-Thompson property. Only
the predicate changes.

## Second defect, same investigation: the evidence is deleted on FAIL

`tools/selfhost_fixedpoint.sh:41` is `trap 'rm -rf "$T"' EXIT` — unconditional.
So on FAIL the `stage_2a` and `tested` binaries go with it, and all that
survives is the message `stage_2a / tested differ: byte 153, line 1`. frankB
could not produce a repro for that reason.

Retaining those two files on failure would turn this class from anecdote into
evidence, cheaply — one `cmp -l` on a real instance.

**Do NOT read the byte offset as a mechanism discriminator.** An earlier draft
of this ticket suggested byte 153 was "early enough to be header rather than
code". frankA hit the same FAIL at byte **339**, and their reading — which I
accept — is that the offset merely tracks where the two images first diverge.
153 and 339 are not two populations, and inviting that inference was a defect in
this ticket, not in the tool.

## Third: a closed ticket may cover a narrower population than its failure mode

`bug-t-gate-sh-fixedpoint-reads-the-live-mutable-compiler` is in `done/`, and
its devtest asserts this FAIL cannot happen. frankB hit it anyway. Their window
does not obviously contain that ticket's mechanism ("compiler/pascal26 replaced
mid-check") — the compiler-touching sibling commit landed *after* the step
finished. What did happen mid-step was a **rebase**, which is a different event.

Recorded as evidence, not as a reopen: rebase-during-check and
binary-replaced-during-check may be two members of one family the guard
currently models only half of. Whoever revisits that ticket should decide;
frankB explicitly declined to assert the mechanism and so do I.

## Known-adjacent, not re-filed

The backgrounded run's task notification said `exit code 0` while the log's own
verdict read `gate: RED (exit 1)`. CLAUDE.md:449 already documents this and
names the count it has misled. This is another instance, on the wide tier rather
than quick — logged here for the tally, not as news.


---

## Second instance, and a real discriminator (frankA via frankB, 2026-09-01)

**Instance 2.** frankA, `gate.sh quick`, same message, byte 339. The NOTE block
named their own just-landed commit; rebuild, re-gate, GREEN with nothing else
changed. frankB's was the **wide** tier and frankA's was **quick**, so this is
not tier-specific.

**The discriminator is the presence of the NOTE block, not the byte offset.**
When gate.sh emits the stale-binary NOTE alongside the FAIL, the observed cases
are a correct-or-stale binary against a moved HEAD — nothing about the pinned
path. **A FAIL *without* that NOTE is the interesting one**, and is the case the
`stage_2a`/`tested` retention above exists to serve. That is a cheap triage rule
someone can apply tonight, before any code changes.

### Why this makes the accidentally-right problem worse, not better

The two instances differ in a way the reader cannot see:

| | NOTE emitted | its premise | outcome after rebuild |
|---|---|---|---|
| frankA | yes, correct | **true** — binary genuinely predated their commit | GREEN |
| frankB | yes, correct | **false** — binary built from exactly those sources; a rebase moved the commit date | GREEN |

Same text, same advice, same green. `stale_binary_hint()` has a single `if` and
one undifferentiated message — verified: five `echo` lines, one condition, no
`elif`/`else` — so it *cannot* say which case it is in, and the reader has no
way to tell either.

**This is the argument for replacing the predicate rather than rewording the
message.** A better-worded NOTE would still be right-for-the-wrong-reason half
the time. `tools/compiler_srchash.sh` answers the actual question — were these
bytes built from these sources — and its answer differs between the two rows
above, which is exactly the discrimination the timestamp test cannot provide at
any threshold.

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
