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
