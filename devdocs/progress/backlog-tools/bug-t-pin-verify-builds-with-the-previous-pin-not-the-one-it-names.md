---
track: T
prio: 70
type: bug
status: backlog
found: 2026-09-02
found-by: claude-T
owner: ""
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
