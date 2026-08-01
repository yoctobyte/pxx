---
summary: "Should ticket Gate: lines prescribe the long local suite, or the 40s native confirm plus Track T offload? Today they say the former while CLAUDE.md says the latter."
type: decision
track: U
prio: 60
---

# Decide: what a ticket's `Gate:` line should require, now that Track T is up

- **Type:** decision (Track U) — **escalated, not guessed**
- **Opened:** 2026-08-01, from a concrete incident this session.
- Blocks half 2 of
  [[feature-t-quick-gate-must-be-quick-and-gate-lines-must-not-name-long-suites]].
  Half 1 (make `gate.sh quick` actually quick) is plain Track T work and does
  not need this answer.

## The fork

Two pieces of guidance disagree, and the ticket is the one in front of you at
the time.

**CLAUDE.md** says: confirm native, offload the matrix. Native confirm =
`testmgr --tier quick` + self-host fixedpoint, ≈40s. Breadth is Track T's job
when a watcher is up; regressions come back asynchronously tied to your sha.

**Nearly every ticket's `Gate:` line** says some form of:

> `make test-nilpy` + self-host byte-identical

which is a **625s local suite** (measured on an idle box this session).

So an agent following its ticket runs locally the exact thing Track T exists to
offload. This is not agents ignoring guidance — I did it this session for
precisely this reason, and the 10-minute window is also what let a concurrent
rebuild invalidate the run (see the T tickets filed alongside this).

## Options

**A. Gate lines become "native confirm; suite via T."**

> **Gate:** `testmgr --tier quick` + self-host byte-identical locally; the suite
> (`make test-nilpy`) via Track T after push.

- Roundtrip per fix drops from ~11min to ~40s.
- master can carry a suite-level red for the minutes until T reports. CLAUDE.md
  already accepts this ("master MAY carry cross-target reds for hours — tstate
  is the truth"), but the Gate lines predate that model.
- Depends on T actually being up. `twatch.py --status` already answers that, and
  the existing rule ("T down ⇒ run your lane's full gate") covers the fallback.

**B. Keep Gate lines as they are; change CLAUDE.md to match.**
- Honest about what is actually required, no async surprises.
- Gives up most of the benefit of having a watcher, and makes every fix a
  10-minute cycle. Contradicts the direction you stated (rely on T, advance
  fast, handle regressions when reported).

**C. Per-ticket judgement — Gate lines say "suite via T" only where the change
is narrow, and keep the local suite for risky/shared-internals work.**
- Matches the real risk gradient (a Track N frontend fix vs. a change to
  `ir*.inc`).
- Costs a judgement call per ticket, and is the status quo that produced the
  current inconsistency, so it needs a written rule to be more than a vibe.

## Recommendation

**A, with C's escape hatch written into the rule**: native confirm is the
default Gate everywhere; a ticket may additionally require the local suite when
it touches shared core (`ir*.inc`, `symtab.inc`, `defs.inc`, the backends, the
P-shared `lexer`/`parser`) — the same file set that already triggers the sole-A
guard. That keeps the fast path for the many narrow frontend/library fixes and
the slow path exactly where a silent break is expensive.

If A is chosen, the existing Gate lines need a sweep; that is mechanical
follow-up work and should be re-filed into the owning lanes rather than done
under U.

## What is NOT being asked

Whether to keep the self-host fixedpoint in the local confirm — keep it. It is
22s, it is the gate that protects the stable binary every track builds on, and
nothing about relying on T changes that.

---

## DECIDED — Option A, unqualified (user, 2026-08-01, at the xeon box)

> "unless track T is proven to be down, we just proceed optimistic
> (`fix worked - native test shows it did`). "

**The rule:**

> **Gate:** `testmgr --tier quick` + self-host byte-identical locally — the
> local native confirm showing the fix works is sufficient to push. The suite
> comes back from Track T afterwards, tied to your sha.
>
> **The only exception is Track T being PROVEN down** (`twatch --status` exit 1,
> or `trackt health` reporting DOWN). Then the pre-existing rule applies: run
> your lane's full gate before pushing anything risky.

"Proven" is deliberate. A slow report, a quiet repo, or a hunch is not down —
`--status` and `trackt health` are the two things that answer it, and both now
read from `origin/master` rather than a stale worktree.

### Option C's escape hatch was recommended and NOT adopted

I recommended A *with* C's carve-out — keep the local suite for changes touching
shared core (`ir*.inc`, `symtab.inc`, `defs.inc`, the backends, the P-shared
`lexer`/`parser`). The user chose plain A. Recorded so a later reader knows the
carve-out was considered and declined, not overlooked.

The reasoning that makes plain A defensible: the one property a bad push could
poison for everyone — a compiler that cannot reproduce itself — **cannot escape
the working tree**, because `make compiler/pascal26` IS the fixedpoint (it
compiles twice and `cmp`s, and refuses to install without convergence). So the
native confirm already covers the catastrophic case, and everything else is a
red on master that tstate reports and someone fixes forward. `pin` remains the
one deliberate brake.

### What this changes in practice

- Existing ticket `Gate:` lines naming `make test-nilpy` are **superseded by
  this convention** — they are not individually rewritten. New tickets should
  use the wording above.
- `gate.sh quick` already matches (`ed7b401b8`: 649s → 58s; `test-nilpy` moved
  to `full`, which is the T-is-down mode).
- Roundtrip per fix: ~11 min → **~24s build + optional 41s gate, verdict in
  ~161s asynchronously** (measured end to end today).

## Log
- 2026-08-01 — decided, commit 73eb0c76d.
