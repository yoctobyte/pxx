---
track: W
prio: 70
type: bug
blocked-by: []
summary: "/opt/pxx-website on `via` has six modified files DEPLOYED AND SERVING pxxc.org since 2026-08-20 that exist in no commit and no branch. UPDATE 2026-08-27: the data-loss half is MITIGATED — a verified out-of-repo backup now exists — but the BLOCKING half stands and this ticket closes only on commit-and-push. Do not close it on the backup. A `git checkout .` or a re-clone destroys them, and one of the six IS the re-clone recovery script. It also silently blocks every other Track W ticket: the deployed tree does not match origin/main, so work branched off origin conflicts on arrival and the documented `git pull --ff-only` deploy step fails."
status: backlog
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

## Why it blocks the rest of Track W

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

Note for whoever picks it up: the backup is itself unreplicated. If the box it
sits on is the box that fails, both copies go together.

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
