---
slug: bug-a-the-fpc-seed-canary-skips-a-break-already-on-master
track: A
prio: 80
type: bug
status: done
blocked-by: []
summary: "gate.sh's FPC seed canary arms only when `git diff merge-base(origin/master,HEAD) -- compiler/` is non-empty. So a seed break that is already ON origin/master is invisible to every clean tree (SKIP, never FAIL), and then fires on the next agent who touches compiler/ — naming a file and a commit that are not theirs. Observed 2026-08-29: two gates printed PASS while the seed was broken upstream, and the break surfaced hours later attributed to an unrelated Track A change."
owner: frankA
---

# The seed canary skips a break that is already on master

Found 2026-08-29 by frankA while gating a Track A fix. Sibling of
`bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build`, which is the
breakage that exposed this; **this ticket is the mechanism**, and it is the one
worth fixing — the R ticket is a one-line deletion, this one decides whether the
next seed break is found in seconds or hours.

## The arming rule

`tools/gate.sh:274-283`:

```sh
seed_base=$(git merge-base origin/master HEAD 2>/dev/null) || seed_base=HEAD
if command -v fpc >/dev/null 2>&1 && \
   ! git diff --quiet "$seed_base" -- compiler/ 2>/dev/null; then
```

The reasoning above it is sound as far as it goes (`:262-273`): arming on HEAD
alone skipped precisely when it mattered — clean tree, work committed, about to
push — so it was moved to the merge-base to cover committed-but-unpushed. And it
deliberately does not arm for "a sibling's compiler commit I merely have not
pulled: their push already ran this."

That last clause is the bug. **It assumes the sibling ran the gate.** The gate
is optional per fix (CLAUDE.md: `gate.sh quick` is OPTIONAL per fix, REQUIRED
before a pin), which is a deliberate and good rule — so "already on origin"
means "nobody objected", not "proven green".

## What it costs

1. **Silent while broken.** A worker with no local `compiler/` change has an
   empty diff → `SKIP`. On 2026-08-29 two gates on this box printed
   `PASS  FPC seed canary` — one at 20:34, eight minutes after the duplicate
   forward landed at 20:26 — because that tree had not pulled it yet. Neither
   run was wrong about what it measured; neither measured the tree that was
   broken.
2. **Mis-attributes on discovery.** The next agent to touch `compiler/` arms the
   canary, it fails, and the error names someone else's file. The failure
   arrives inside *their* gate, on *their* change, at the moment they are about
   to push. The natural reading is "I broke it", and the natural next move is a
   bisect. That is the hour this ticket is really about.
3. **The failure text points the wrong way.** `gate.sh:305-307` prints
   "a routine is called from an include EARLIER in compiler.pas than the file
   defining it — add a forward". Here the defect was the opposite (a forward
   too many), so the advice actively misdirects. Worth widening to name both
   shapes, or to just print the FPC error and stop diagnosing.

## Proposed fix

Keep the cost argument — one seed build per `origin/master` advance, concurrent,
~11s — but stop treating "already on origin" as "already proven". Record the
last sha the canary was green on (e.g. `.git/pxx-seed-green`), and arm when
EITHER:

- `git diff merge-base -- compiler/` is non-empty (today's rule), OR
- `origin/master` has moved past the recorded green sha in `compiler/`.

Then a break on master is caught by the first gate anyone runs after pulling it,
attributed to the pull rather than to the puller's change, and a repo that is
sitting still still costs nothing.

A cheaper 80% variant if the state file is unwelcome: when the canary FAILS,
re-run it once at `merge-base` and say which side it came from —
"seed was ALREADY broken at origin/master (not your change)". That does not make
it visible sooner, but it removes the mis-attribution, which is the expensive
half.

## Related

`tools/forwardlint.py` — the ~3s check at the same gate step — finds MISSING
forwards and not DUPLICATE ones, so it passed here too. Detecting "the same
routine forwarded twice in one file" is a few lines and would move this class
from a minutes-long failure to a seconds-long one. Noted in the R ticket.

## Gate

`tools/gate.sh quick` on a tree whose only defect is upstream must report the
seed FAIL, not PASS/SKIP — verifiable today by checking out `fa238413e`, which
carries the live duplicate-forward break, with a clean working tree.

## Log
- 2026-08-29 — resolved, commit 49a21b84d.

## Resolved 2026-08-29 — frankA

Second arming rule in `tools/gate.sh`: the canary also fires when
`origin/master`'s `compiler/` has moved past the last sha **this clone** proved
green, recorded in `$GIT_DIR/pxx-seed-green`. Untracked and per-clone on
purpose — "seed-green" is a property of a box that ran fpc, not of a commit,
and tracking it would let one box's green silence every other box. The sha is
recorded only when the working tree's `compiler/` is clean against HEAD;
with edits in flight, what was proved is not any sha, and stamping HEAD would
suppress the next run for a state never built.

The misattribution half is fixed at the same time, and it is the half that
costs hours: on FAIL the gate now leads with whose break it is, from
`seed_mine` (does this tree have any local `compiler/` change at all), before
saying what it might be. It also names BOTH failure shapes — the existing
MISSING-forward advice actively misdirected here, where the defect was a
forward too many.

**Verified on the live defect, before and after.** On this tree, clean, with
the duplicate forward sitting on origin/master:

- old rule — `git diff merge-base -- compiler/` empty → not armed → `SKIP`,
  break unreported. Two gates on this box had printed `PASS` for exactly this
  reason earlier in the day.
- new rule — nothing proved on this clone → armed → runs fpc → `FAIL`, with
  `NOT YOUR CHANGE: no local compiler/ edits — this break is already on
  origin/master. Do not bisect your own work.`

Gate: `tools/gate.sh quick` at `71dd35092`, self-host fixedpoint `60b060bb54a8`.
The seed step went RED as designed; every other step passed. That RED was the
upstream duplicate forward, since deleted by Track R in `20efe74ef`.

Not done here, deliberately: `tools/forwardlint.py` gaining duplicate-forward
detection — the coordinator took that and landed it as `52eb9dc2f`.

<!-- COORDINATOR NOTE 2026-08-30: the section above was CONCATENATED in from a
second copy of this ticket that was sitting in working/. Two files, one slug, in
two status folders -- and they were complementary, not duplicate: done/ carried the
ticket, working/ carried this resolution write-up and nothing else.

That is why the lock looked live for four hours after the fix landed. Every
ownership scan reads the FOLDER, so a stray copy in working/ is a phantom lock on
a ticket that is finished, and it is indistinguishable from a real one. The
working/ copy also had no frontmatter, so it answered no question about who held
it either.

Concatenated rather than deleted, per the standing rule for exactly this shape.
`progress check` now has a DUPLICATE-SLUG scan so the next one is found in seconds
rather than by a git mv refusing to overwrite. -->
