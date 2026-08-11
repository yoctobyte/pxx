---
track: T
prio: 80
type: task
summary: "Track A pins in 30s and never waits; everything heavier moves to Track T, asynchronous and per-sha. Status is a JOIN of pin.log x tstate, not a label on the pin. Native full regression (incl. NilPy + corpus) is the priority right now, above the cross matrix."
status: done
owner: claude@plexus
---

# Pinning is fast and unverified; Track T owns verification

**Decided by the user, 2026-08-09.** Filed for Track T because T owns the
hardware (12 Xeon cores) and the reporting; Track A has already done its half.

## The principle

> **Track A+ work should never wait long — not even when Track B asks for a
> fresh pin.**

A pin exists to hand other tracks a working compiler. While it runs, those
tracks AND the human are blocked. So the pin path is 30 seconds, always, and
every heavier thing happens *after* it, asynchronously, on T's machine.

## What Track A already changed (done, v252)

- `make stabilize-fast && make pin` — **34s measured** (`test-quick` + the
  self-host `self→next→fixedpoint` byte-identity chain, then symlink moves).
- The old default was `make stabilize`, which **depends on `make test`** — the
  full native suite. Every pin was paying ~25 minutes. `stabilize-fast` already
  existed with the right bar; its own comment told agents not to use it for real
  pins. That comment and CLAUDE.md's Track A line now carry the new policy.
- Full `stabilize` remains available for a release, or when T is proven down.

Nothing below asks Track A to change anything further.

## What NOT to build

An earlier draft proposed a promotion ladder — `pinned` → `verified` →
`release`, three labels on the artifact. **The user rejected it and was right.**

Status is a property of a **sha**, and T already tracks that per-sha. A label on
the pin stores the same fact twice and goes stale the moment T learns something
new. So:

- one artifact, one pointer (`pinned`), no labels;
- "what is the status of the current pin?" is a **JOIN**: take the sha from
  `stable_linux_amd64/default/pin.log`, look it up in `tstate/`.

That also disposes of a layout problem the ladder would have created (the
single shared `default/builtin/` freeze cannot serve labels sitting at different
shas). Do not build labels, tiers or promotion until something actually hurts.

## Deliverable 1 — make the join one command

`tools/trackt.py pinstatus` (name negotiable), printing something like:

```
pin v252  32c8423c  dcd323d9  2026-08-09T15:43Z
  quick   GREEN
  full    RED  test-nilpy#src:test/foo.npy (aarch64)
  last pin T found fully green: v250  (a1b2c3d4)
```

The last line is the point. **A bad pin is recovered, not prevented** — that is
the whole trade the fast pin makes — and recovery needs somewhere to fall back
to. Without this the join is manual, and a manual join is the one nobody does
when it matters. Pair it with `make revert` so demoting is as cheap as pinning.

## Deliverable 2 — run the right matrix, in the right order

The thing being hunted is **two-dimensional: test cases x platforms.** Both axes
are expensive and they are NOT equally valuable right now.

**Native depth first, platform breadth second.** Specifically:

1. **Native x86-64, ALL frontends, full** — Pascal `make test`, **`test-nilpy`**,
   C, plus corpus subjects (**uforth**, and the other real programs). Run this
   often; it is where the yield is.
2. **Cross matrix under qemu** (i386/aarch64/arm32/riscv32/xtensa) — slower by
   an order of magnitude, run less often.

### Why NilPy is in tier 1 and not an afterthought

**NilPy is a main target now.** The earlier framing — "only Pascal matters,
because only Pascal can corrupt self-hosting" — is correct about *self-hosting
integrity* and wrong as a *priority*. Self-host integrity is not the only thing
worth protecting; NilPy is a first-class frontend with a real corpus, and at
this stage of its development **fixing one bug routinely uncovers others**, so a
full native NilPy regression pays for itself on nearly every run. This session
alone: a `__setitem__` gate fix immediately exposed the `del`-target sibling
(which was already red on master), and a lambda fix exposed five unrelated
builtin segfaults.

### Why byte-identical self-compile is NOT enough (the justification for tier 1 at all)

Worth stating because it is the non-obvious part, and it is what makes a heavier
tier worth running even though the fast pin is green:

> A byte-identical fixedpoint proves the compiler reproduces itself **through
> the paths the compiler itself exercises**. A codegen bug in a construct
> `compiler.pas` never uses is invisible to it, forever.

That gap is exactly what the regression suites cover and what `quick` may miss.

## Suggested shape

- T keeps publishing per-sha reports as it does today; nothing about tstate's
  format needs to change for `pinstatus` to work.
- T may treat "a new sha appeared in `pin.log`" as a trigger to run tier 1
  against it promptly, so the pin the tracks are actually using is the one that
  gets attention first.
- A tier-1 RED on the current pin is worth surfacing loudly (it is what the
  tracks are building against); a cross-matrix RED is an ordinary ticket.

## Gate

Track T's own: `tools/testmgr.py --tier full` green for tooling changes, and
`pinstatus` exercised against a real `pin.log` + `tstate/` pair rather than a
synthetic one.

---

## RESOLVED 2026-08-11 — all three deliverables in; the last one was the gap

**Deliverable 1 — `pinstatus`.** Landed earlier in `bb461b937`. The join, the
per-tier lines, and the last-fully-green fallback all work against the real
`pin.log` x `tstate/` pair.

**Deliverable 2 — native depth before platform breadth.** Landed earlier in
`e347d187a` (`limited` became the native-depth tier: all frontends, `test-nilpy`
and `test-uforth`, the real corpus, no qemu) and `c32381c4f` (the idle
escalation ladder). NilPy is tier 1, as this ticket asked.

**The "suggested shape" bullet was the one that mattered, and it was never
built:**

> T may treat "a new sha appeared in `pin.log`" as a trigger to run tier 1
> against it promptly, so the pin the tracks are actually using is the one that
> gets attention first.

`twatch` never read `pin.log` at all (`grep -c pin.log tools/twatch.py` = 0).
Measured over `pin.log` x `runs-*.ndjson`, that is not a rounding error:

| of the last 25 pins | count |
| --- | --- |
| got a `full` run | 7 |
| got `native` only | 2 |
| **never judged in ANY tier** | **13** |
| **never got a `full` run** | **18** |

And it was live while this ticket was being read: **v257 (`96b4b40a`), pinned
2026-08-11T16:18Z, `NOT JUDGED`** — the binary every other track had been
building with for an hour.

This is not a bug in the ladder; it is a gap the ladder *cannot* see. The
ladder deepens HEAD, and a pin is whatever HEAD happened to be when a human ran
`make pin` — by the time the box climbs from the fast tier to depth, HEAD has
moved and the pin is history. The pin was covered only by the accident of
still being HEAD when T looked. So the recovery half of this ticket's own
trade — "a bad pin is RECOVERED, not prevented" — had nothing to recover from,
because no verdict was being produced for the artifact in question.

**Landed:** a pin-verification phase in `twatch`, at two priorities.

```
1. new push        -> fast tier on HEAD        seconds; nobody waits on T
2. PIN, mid tier   -> native depth on the PIN  <- new, and ahead of HEAD's idle
3. idle            -> mid tier on HEAD            depth on purpose
4. still idle      -> deep tier on HEAD
5. PIN, deep tier  -> platform breadth on the PIN  <- new
6. opt / bench / bisect / fuzz
```

Native depth on the pin outranks idle depth on HEAD because that binary is what
Tracks B/C/D/E are compiling against *right now*, while HEAD is a sha nobody
has adopted. Platform breadth on the pin waits its turn — it is ordinary work,
and it is what gives `pin_is_green` (which requires a `full` run) a fallback
target to name.

Two design points that were easy to get wrong, both recorded in
`devdocs/dev/track-t.md`:

- **It does not go through `test_sha`.** That function maintains the HEAD
  progression — `last`, `jobs`, the open-regression ledger — all defined
  relative to the sha sequence the host walks. Feeding it a days-old pin would
  set "last tested" backwards, diff the pin's job map against HEAD's and
  manufacture NEW-RED/FIXED pairs out of nothing but the time travel, and open
  regressions whose commit range means nothing. `verify_pin` publishes exactly
  one run record and touches no state another phase reads.
- **A box that could not measure publishes nothing** (INFRA/INVALID/no
  measurement all bail). An unjudged pin is a known unknown; a fabricated
  verdict on the artifact every track builds against is much worse.

A RED on the pin prints loudly and names both recovery routes (`pinstatus` for
the last fully-green pin, `make revert` to demote), per this ticket's
"surfacing loudly" note.

**Also fixed while here:** `pin-verify` is a long phase that is not
`"testing"`, and `trackt`'s wedge detector keyed on that exact string — so the
longest new phase would have been its one blind spot. Both `health_check` and
the attach/progress view now key on a `GATE_PHASES` tuple. (The heartbeat
itself was already safe: `run_gate` refreshes it every 30s regardless of phase
name.)

**What this ticket does NOT do**, deliberately: it does not move `pinned`, and
it does not auto-revert. Those belong to
[[decide-track-t-autopin-criteria]], which is in shadow mode and has four
questions still open before a live cutover. This ticket only makes the pin's
status a *measured fact* instead of an accident — which is the precondition for
any of that, and is worth having on its own.

**Verified:** `tools/devtest_pin_verify.py` (9 checks — both `pin.log` line
shapes, the already-judged skip, the mid-before-deep split, the
unreachable-pin guard, missing files); `devtest_pinstatus`, `devtest_idle_ladder`,
`devtest_pin_shadow`, `devtest_skip_semantics`, `devtest_stub_lifecycle` all
still green; `trackt health` / `pinstatus` exercised against this box's real
daemon and real `pin.log`.

**End-to-end, on the live daemon** (restarted to pick it up — `twatch.py` has
no hot reload, which is why the shadow-mode cutover needed the same thing):

```
twatch: 3915a1289f41..22226d7acb7c is docs/tstate-only — no gate needed
twatch: verifying PIN v257 (96b4b40ab6c5) at limited — the sha every other track builds on
```

and `trackt status` rendering the new phase:

```
daemon : RUNNING pid 3855625 — pin-verify sha=96b4b40ab6c5 tier=limited
```

v257 had **no judged tier at all** when this fired, which is the ticket's whole
point demonstrated on the pin that happened to be current.

The **preemption path** was exercised in the same window — a sibling track
pushed mid-verification:

```
twatch: pin verify preempted by a push — will resume
```

Clean teardown, no verdict recorded, retried on a later quiet cycle. That is
the required behaviour: pin verification must never delay a fresh push's fast
verdict, and a half-run must never publish.

## The cost, stated plainly

This is not free, and the trade should be watched rather than assumed:

- a pin now costs a `limited` run **and** a `full` run on top of HEAD's ladder,
  roughly 12-15 minutes of box time per pin at current tier walls (less now
  that `test-uforth` is sharded — the two changes in this session pull in
  opposite directions and the sharding is the larger term);
- pins land a few times a day, so that is a small fraction of the box. But if
  pinning ever becomes frequent, `pin_deep` sits **above** opt/bench/fuzz in the
  chain and would squeeze them first. If those phases start starving, moving
  `pin_deep` below `opt` is the knob — the mid-tier verification is the part
  that must stay high.

`pin_mid` can never starve HEAD: a new push is checked first and always gets
its fast verdict before anything here runs.

## Log
- 2026-08-11 — resolved, commit 9069f0947.
