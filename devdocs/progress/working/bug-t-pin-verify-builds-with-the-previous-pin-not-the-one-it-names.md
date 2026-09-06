---
track: T
prio: 80
type: bug
status: working
found: 2026-09-02
found-by: claude-T
owner: frank-subcoord
blocked-by: []
summary: "verify_pin() does clone.checkout(<the pinned TREE>), which also checks out stable_linux_amd64/** as of that tree. A pin commit is always a DESCENDANT of the tree it pins, so the checked-out binary is the PREVIOUS pin. Every pin verify therefore builds its $(PXX_STABLE) targets with pin v(N-1) while recording the verdict under vN. Evidence: one run logs `verifying PIN v400 (67ae9a62d567)` and then `testmgr: pin=399 sha256=954adef93a7b`; `pin=400` appears ZERO times in the whole watcher log. The already-closed bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label saw this exact symptom (`ver said v347 while the verified tree carried pin 346`) and fixed the LABEL."
---

# `verify_pin` builds with the previous pin, and files the result under the new one

## The mechanism, and it is structural rather than a race

`verify_pin()`:

```python
print("twatch: verifying PIN %s (%s) at %s …" % (ver, sha[:12], tier))
set_phase(clone, host, "pin-verify", sha=sha[:12], tier=tier, pin=ver)
clone.checkout(sha)          # <- the pinned TREE
report, rc = run_gate(clone, tier, …)
```

`clone.checkout(sha)` brings the whole worktree to that sha — including
`stable_linux_amd64/**`. And **a pin commit is always a descendant of the tree
it pins**: you cut the pin at tree `T`, then commit the new binary as a child of
`T`. So at `T`, `stable_linux_amd64/default/pinned` still holds **v(N-1)**.

`lib-test`, `demos` and `test-fpjson` build with `$(PXX_STABLE)`. They therefore
build with the previous pin, every time, by construction.

## Evidence — one run, three lines

```
twatch: verifying PIN v400 (67ae9a62d567) at full — the sha every other track builds on
self-host fixedpoint: verified — 1 round(s), 6c184b4bcc37 (stamp read back; sources match it)
testmgr: compiler snapshot /tmp/…/compiler/pascal26 (sha256 6c184b4bcc37)
testmgr: pin=399 sha256=954adef93a7b0e9e (lib-test and demos build with THIS, not HEAD)
  [   4/3846] FAIL    lib-test#60                     1.6s
```

The HEAD compiler is v400's bytes (`6c184b4bcc37`). `$(PXX_STABLE)` is
**v399** (`954adef93a7b`). `grep -c 'pin=400' trackt-watch.log` → **0**.

`report_pin_identity()` — the function written so a lib-test red says which
binary produced it — printed the correct answer, and nothing read it.

## What it produced this time

The v400 verify recorded 5 reds:

```
lib-test#src:tools/crtl_reachability.py
lib-test#src:test/lib_synapse.pas
lib-test#src:test/lib_synapse_transitive_unit.pas
lib-test#src:test/lib_synapse_ssl.pas
tools-devtest#00
```

Those are **v399's** known defects, verified as such: v399 fails
`lib_synapse` with `cannot assign ShortString to Char` and v400 builds it
clean, measured both ways under `srchash MATCH`. The verify attributed v399's
breakage to v400 in the record every other track reads.

## Why this matters more than one bad record

It runs backwards through the history. Each pin verify is a judgement of the
**outgoing** pin wearing the incoming pin's name:

- `v400 at 67ae9a62d` — 5 red — actually v399, and v399 is independently
  known-broken (two SIGSEGVs, the synapse trio, the `8b89a201d` ModRM
  miscompile).
- `v399 at 86c71828cd1e` — "20 red, 19 new vs the v399 baseline" — actually
  v398, the pin that could not build C for i386 or arm32.
- `v398 at c8e132a02b92` — "5 red, 4 new" — actually v397; annotated by hand as
  *"NOT CORROBORATED … a load-shaped flake, do NOT revert on this count alone."*

That last annotation may be the real cost. The reds were not flakes. They were
true statements about a **different binary**, and a careful human read them as
noise because they did not reproduce at HEAD — which is exactly what a
previous-pin red would do.

## This was already seen once and fixed at the wrong level

`bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label`
(now in `done/`) records:

> *"And its `ver` said v347 while the verified tree carried pin 346."*

That is this bug, observed exactly. It was read as **the label being stale** and
the label was corrected. The label is now right and the binary is still the old
one, so the disagreement it noticed has been resolved in favour of the wrong
side — the record is now confidently mislabelled instead of visibly
inconsistent.

## Fix — options, not a prescription

1. **Restore the pinned binary after checkout.** Check out the tree, then
   overwrite `stable_linux_amd64/default/pinned` (and the frozen `builtin/`)
   from the pin commit being verified. Most faithful to the question "is this
   pin good?", and the pin commit is a known sha.
2. **Verify at the pin COMMIT, not the pinned tree.** Simpler, one-line-ish, but
   it changes what is being tested — the pin commit's tree may carry other
   changes.
3. **Refuse to verify when they disagree.** Compare
   `report_pin_identity()`'s answer against `ver` and abort with a loud message
   rather than record. Cheapest, and turns a silent wrong record into a visible
   gap — the direction this repo consistently prefers.

Whatever is chosen, **assert the two agree**, because the evidence that they do
not was printed in the log all along and read by nobody.

## Positive control for any fix

A verify of `v400 (67ae9a62d567)` must log `pin=400 sha256=6c184b4bcc37`, and
its `lib_synapse` jobs must be GREEN — v400 builds all three, measured. Under
today's code the same verify logs `pin=399` and fails them.

---

## Second instrument, same defect, one hour later — and the gap is measured

Re-ranked 70 → 80 on this, not on the original finding. One instrument getting a
pin identity wrong is a bug in that instrument; **two independent ones within an
hour is the identity itself being easy to get wrong**, and everything that
quotes a pin is exposed.

**The second instance** (coordinator, on `umbrella-sizeof-is-one-answer`): a pin
ancestry table checking whether three closed tickets' *pinned positive controls*
had gone stale. It resolved the pin as commit `766b99f98` — the
`chore(stable): pin v401` commit — rather than `07d196aa4`, the tree v401 was
built from. Caught before it moved a conclusion: none of the three controls sits
in the gap, so all three were still VALID. Anything that did sit in the gap would
have returned a **false VALID**.

That is not this ticket's mechanism — `verify_pin` checks out the tree and gets
the old binary; the table read the commit and got a too-new tree — but it is the
same root confusion, from the opposite end: **the pin commit and the pinned tree
are different objects and neither name says which one it is.**

**The gap is not incidental, and it is not small.** Measured across the three
pins cut on seven:

| pin | commit | tree | commits between |
| --- | --- | --- | --- |
| v401 | `766b99f98` | `07d196aa4` | **4** |
| v400 | `3e05d2946` | `67ae9a62d` | **2** |
| v399 | `a7abc2481` | `86c71828c` | **3** |

Never zero. The pin is cut at tree `T`, then `stabilize-fast`, `pin`, commit and
a rebase loop against a busy origin all take minutes, during which the fleet
lands work. So the pin commit is 2–4 commits ahead of the tree it describes, and
that distance grows with fleet activity rather than shrinking.

Concretely for v401: `dfff555e0`, `d6b222419` and `10916bd26` are inside the gap
and are *not* in the pinned binary, but any check that resolves "the pin" to
`766b99f98` will believe they are.

**What this adds to the fix list.** Alongside the three options above, the
cheapest general remedy is naming: `pin.log` already records both — the git sha
column is the TREE. Any consumer resolving "the pin" to a commit should be
reading that column, and a helper that returns the pinned TREE for a version
would make the right answer the easy one. Two instruments got this wrong in an
hour by each deriving it independently.

**Positive control for that helper**, from the table above: given `v401` it must
return `07d196aa4`, not `766b99f98`, and `git rev-list --count 07d196aa4..766b99f98`
must be 4.

---

## The gap is 17 commits at v407, and the ticket predicted the direction

Re-measured 2026-09-06 (frank-subcoord, on claiming this). The table above
recorded 2–4 commits between the pin COMMIT and the pinned TREE across
v399–v401, and predicted the distance "grows with fleet activity rather than
shrinking". Confirmed, and by more than the original range suggests:

| pin | commit | tree (pin.log's sha column) | commits between |
| --- | --- | --- | --- |
| v401 | `766b99f98` | `07d196aa4` | 4 |
| v406 | `ab72ab352` | `1b903c1dd` | 6 |
| **v407** | **`51901941e`** | **`04559b9d6`** | **17** |

The v401 positive control this ticket specifies still passes exactly:
`git rev-list --count 07d196aa4..766b99f98` = 4.

**What is inside the v407 gap and NOT in the pinned binary** includes
`2f1fe06b9 fix(P): a routine-local type section is parsed in PASS 2, so its
specialize splice must move the spans` — a compiler fix. Anything resolving
"the pin" to `51901941e` believes those 17 commits are in the binary
`095ef4811a5b`. They are not.

## Caught live, in a request, in the direction that helps

frankuser queued a full tier in `verify-requests.tsv` at `51901941ef5d` with the
reason *"pin v407 (binary 095ef4811a5b) was cut at this tree"*. It is not the
tree — it is the pin COMMIT (`chore(stable): pin v407 -- binary sha256
095ef4811a5b`); pin.log's sha column gives the tree as `04559b9d6`
(`docs(roster): the night a correct measurement froze the fleet`).

**The error landed on the useful side.** Because `stable_linux_amd64` at the pin
commit holds v407, that request measures the v407 binary — which is what anyone
asking "is this pin good?" wants. `verify_pin` checks out the TREE and therefore
builds every `$(PXX_STABLE)` job with **v406** while filing the verdict under
v407. So a hand-written request got the right answer by naming the object this
ticket says is the wrong one, and the automated path gets the wrong answer by
naming the right one.

That is empirical support for **option 2** (verify at the pin COMMIT) over
option 1, and it is worth more than the abstract argument: at the pin commit the
pinned binary is vN by construction, with no restore step that can itself fail.
The cost option 2 was charged with — "the pin commit's tree may carry other
changes" — is now measured at 17 commits, so it is a real cost and not a
rounding error. **Neither option is free, and the choice is between building the
right binary against a slightly newer tree (option 2) and reconstructing a state
that never existed (option 1).**

Three sessions confused these two objects in one evening. The naming remedy this
ticket already proposes is the load-bearing part.
