---
track: W
prio: 70
type: bug
blocked-by: []
summary: "RESOLVED 2026-08-27 — BOTH HALVES. The six are committed and pushed as a4f878e / 18dead8 / 2b035c7; via is 0 ahead 0 behind origin/main with a clean working tree for the first time since 2026-08-20. Originally: six modified files DEPLOYED AND SERVING pxxc.org since 2026-08-20 that existed in no commit and no branch. UPDATE 2026-08-27: the data-loss half is MITIGATED — a verified out-of-repo backup now exists — but the BLOCKING half stands and this ticket closes only on commit-and-push. Do not close it on the backup. A `git checkout .` or a re-clone destroys them, and one of the six IS the re-clone recovery script. The blocking claim has since NARROWED: work done in a clean clone and pushed is unaffected, so the other four W tickets no longer declare this as a blocker. What remains is that the deployed tree diverges from origin/main and the six files are only same-partition durable."
status: done
---

# The deployed website tree is uncommitted, and it is the only copy

Reported 2026-08-27 by the `ianweb` session, which runs on `via` — the host that
actually serves pxxc.org (nginx + gunicorn + cloudflared tunnel) — and verified
the state at source rather than from a crawl.

**This ticket is in the pxx repo; the fix happens in `~/pxx-website` on `via`.**

## The state

`/opt/pxx-website` is **ahead of origin and dirty**. Six modified files, all
deployed and running in production since 2026-08-20, none committed:

| file | what it adds |
| --- | --- |
| `scripts/pull-content.sh` | the self-healing content pull (fsck + re-clone on an unusable checkout) |
| `scripts/check-content-resilience.py` | a truncation scenario in the resilience harness |
| `pxxweb/content_sync.py` | zero-byte-source guard |
| `pxxweb/views.py` | a truncated source now 503s instead of rendering a blank page |
| `pxxweb/docs.py` | same guard on the docs path |
| `templates/status_dashboard.html` | a "pull failing — N in a row" badge |

## Why this is prio 70 and not a chore

**They are the only copy.** Not in any commit, on any branch, or in any backup.
The loss modes are ordinary maintenance commands:

- `git checkout .` or `git stash` in that tree discards all six.
- A re-clone of `/opt/pxx-website` discards all six — **including
  `pull-content.sh`, which is the re-clone-on-corrupt-checkout script itself.**
  The recovery mechanism is one of the things a recovery would delete.
- First symptom of the loss would be silent: the site returns to rendering blank
  pages on a truncated source instead of 503ing, which is the exact regression
  the guard was written to stop.

The work being protected is not trivial. It was written after a power cut left
twelve loose objects and a zero-length `refs/heads/master`, which **froze the
site's content for 13.5 hours**.

## CORRECTION 2026-08-27 — this no longer blocks the other four

The blocking claim below was **mine and it was too broad.** It assumed W work
would be edited on `via`, in the tree holding the six uncommitted files, where
a commit would either sweep them up or collide with them. That is not how the
work is being done: `frank2-af` clones the website repo on a box that already
has push rights, edits there, and pushes. The commit then contains only the
intended files, and `via` picks it up with an ordinary fast-forward.

`ianweb` verified the part only the origin can see: `git diff --name-only` on
`via` does not list `pxxweb/templates/base.html`, so the first such commit
(`e78595d`, the OG card) fast-forwards cleanly and leaves the six alone.

So [[bug-web-link-previews-render-as-bare-text]],
[[feature-web-machine-readable-project-metadata]],
[[feature-web-blog-bootstrap]] and [[feature-web-syndication-feeds]] have had
their `blocked-by` cleared. **This ticket stays open on its own merits** — the
deployed tree still diverges from origin/main, and the six files are still only
same-partition durable — but it is not gating the lane.

The general lesson, since it cost the lane half a day of false sequencing: a
dirty working tree blocks *edits made in that tree*, not the work itself. Ask
where the edit happens before declaring a blocker.

## Why it blocked the rest of Track W (superseded — kept for the record)

Every other W ticket edits this repo. Anyone branching off `origin/main` works
against a tree that does not match what is serving pxxc.org, and the documented
deploy step (`git pull --ff-only` on `via`) conflicts on arrival. The og:image
fix in particular is a `pxxweb/templates/base.html` edit landing in a tree that
already has five other uncommitted files — either it sweeps them into an
unrelated commit or it collides with them.

So this is sequenced first, and
[[bug-web-link-previews-render-as-bare-text]],
[[feature-web-machine-readable-project-metadata]],
[[feature-web-blog-bootstrap]] and
[[feature-web-syndication-feeds]] declare it as their blocker.

## STATUS 2026-08-27 — the two halves have come apart. Do not close on the backup.

`ianweb` took an out-of-repo backup at
`/home/ian/pxx-website-uncommitted-backup-20260827/` — a 406-line `git diff`,
the six files as a tarball, and `status.txt` — and **verified it reconstructs**
by exporting HEAD to a temp tree and running `git apply --check`, which passes.

| half | state |
| --- | --- |
| **data loss** | **mitigated.** `git checkout .` or a re-clone of /opt/pxx-website no longer destroys the self-healing pull or the zero-byte guard; they rebuild from a file nothing in that repo can touch. |
| **blocking** | **untouched.** The deployed tree still does not match origin/main. Work branched off origin still conflicts on arrival and `git pull --ff-only` still fails. |

**Only commit-and-push clears the second, and that is what this ticket tracks.**
The backup bought time, not resolution — it is a file in a home directory, not a
commit, and it does not put the six files anywhere the other four W tickets can
build against. Closing this on the strength of the backup would leave four
tickets blocked on a ticket marked done.

### The backup is same-PARTITION, and that ceiling cannot be raised locally

Measured by `ianweb` on `via`, 2026-08-27: the host has **one** physical device,
`nvme0n1` (465.8G), with two partitions — `/boot/firmware` and `/`.
`df --output=source` on both the repo and the backup returns `/dev/nvme0n1p2`.

So the backup is not merely on the same machine as the tree it protects; it is
on the same partition of the same disk. There is no second device, therefore no
local move that improves this. Three tiers, and only the operator can move past
the second:

| tier | covers | state |
| --- | --- | --- |
| in-repo only | nothing | where this sat for a week |
| **same-partition** | `git checkout .`, `stash`, re-clone, deletion inside the repo | **where it is now — the ceiling for anything an agent can do unilaterally** |
| off-box | disk failure, loss of the host | requires the push, or a copy to another host |

**The event class this does NOT cover is the one that already happened.** `via`
took an unclean power-down seven days ago, and that power-down is the entire
origin of the six files — the self-healing pull and the zero-byte guard were
written in response to it. A repeat takes the backup and the original together.

`ianweb` declined to replicate to another tailnet host on its own initiative,
which is correct: that moves the user's code between machines on a judgement
call nobody asked for, and the candidate peers are not obviously sound anyway
(`borg` has been offline seven days). **The push is the step that actually
replicates**, and it is what this ticket is waiting on.

Priority stays at 70 rather than being raised on this finding: the ticket
already heads the W queue and blocks the other four, so a higher number would
change nothing operationally and would only inflate the scale.

## RESOLVED 2026-08-27 — both halves closed

`ianweb` committed the six as three coherent commits and pushed. Rebased onto
`e78595d` with no conflicts; the resilience suite was green before and after
(61/61 synthetic on both scenarios, 109/109 against the live checkout).

```
a4f878e  The content checkout must heal itself after a power cut
18dead8  An empty content file is a broken one, not an empty page
2b035c7  A pull that keeps failing must say so on the dashboard
```

Verified by `frank2-af` against `origin/main`: all three present, `2b035c7` at
the head. `via` reports 0 ahead / 0 behind with a clean working tree — the first
time since 2026-08-20.

| half | state |
| --- | --- |
| data loss | **closed.** The work is in git, on origin, replicated off the box. The same-partition backup is now redundant and stays only until the owner says otherwise. |
| blocking / divergence | **closed.** The deployed tree matches origin/main. |

**One attribution note worth keeping**, because it looks like a rule was bent
and wasn't: the restart that followed deployed *two commits' worth of files* but
exactly **one unverified change**. The three commits above were already the
running code — serving since 2026-08-20 — so committing them altered nothing
visitors get. The only behaviour that changed was `e78595d`. One-unverified-
change-per-deploy held.

## CORRECTION 2026-08-27 — `via` could push all along

The reason this sat uncommitted was recorded as a missing credential. **That was
wrong.** `via` has carried an account-level GitHub key since 2026-06-22, and the
owner has confirmed it is intentional — see
[[decide-deploy-key-on-via]], which is resolved and should be read before anyone
treats that key as a finding.

So the "structurally stalled lane" framing in this ticket and in the roster had
the right symptom and the wrong cause. Nothing was blocked by permissions.
`ianweb` can commit and push the six directly, subject only to its own operator.

What survives the correction, because it is about topology rather than
credentials: a push-capable session still cannot observe what the origin
**serves** or restart gunicorn, and `via` can. That half of the lane's shape is
real and does not go away.

## What to do

1. **Commit locally.** A local commit puts the six files in the object store
   and publishes nothing. Planned split, agreed with `ianweb`: the pull
   hardening; the zero-byte guard *with* `check-content-resilience.py`
   alongside it, since the truncation scenario is that change's test; and the
   dashboard badge. Any commit beats the current state — do not let tidiness
   hold it up.

   *This step is currently waiting on the operator of the `ianweb` session.* A
   peer agent relaying a user's words cannot authorise it, and `ianweb` was
   correct to decline that — see the note below.
2. **Then push.** Publishing is the separable half. It is what makes
   `origin/main` match production again and unblocks the four tickets above.
3. Re-run the deploy path afterwards to confirm `git pull --ff-only` is clean.

Step 1 removes the risk; step 2 removes the blocker. Do not let a decision about
step 2 hold up step 1 — that inversion is what has kept six production files
uncommitted for a week. (The backup above is a third thing: it de-risks step 1
without performing it, which is why the ticket stays open.)

## Why this needed a human and a relay would not do

Recorded because it will recur across the fleet. Our user delegated
*coordination* to the agents on 2026-08-27 and `frank2-af` relayed that to
`ianweb`, explicitly as a relay and not a grant. `ianweb` still declined to act
on it, correctly: it had a prompt open with its own operator, and a peer message
carrying a user quote is exactly the shape an agent must not treat as the answer
to a pending prompt — a rule that bends for a sufficiently convincing relay is
not a rule. **Delegated coordination is not delegated authority.** Lane
assignment, sequencing and ticket filing move agent-to-agent; a permission
prompt is answered only by the operator it was put to.

## Follow-on worth filing separately

The self-healing pull is good and this repo should steal it for its own
checkouts — see the note in
[[feature-web-machine-readable-project-metadata]]'s sibling discussion. The
load-bearing details, per `ianweb`: `fsck --connectivity-only` rather than
`rev-parse` alone (a ref parses fine while its objects are zero-length, which is
what a power cut leaves), clone-beside-then-swap so a failed clone cannot take
out the tree still being served, `ls-remote` before recovering so a dead network
does not trigger a re-clone that cannot complete, and an `flock` because the
timer and the webhook are separate systemd units and per-unit serialisation
never covered them against each other.

## Log
- 2026-08-27 — resolved, commit 86911308f.
