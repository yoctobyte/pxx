---
slug: decide-where-a-persistent-fpc-trunk-oracle-lives
track: U
type: decide
prio: 30
status: decided
blocked-by: []
summary: "RULED 2026-09-01 (owner): option B — a persistent build at ~/src/fpc-trunk, refreshed ON REQUEST by tools/fpc_trunk.sh. Manual refresh is the ruling, not a shortcut: nightly-build testing is rare, and CLAUDE.md forbids anything timed. The script encodes the three traps from the recipe below. NOTE the recipe here is STALE in one line — ~/src/fpc-source does not exist and ~/src did not either; the script clones from GitLab when the mirror is absent. ORIGINAL: The FPC trunk oracle works but has nowhere to live: a trunk build is ~4 min and ~1GB, it must sit OUTSIDE the repo, and installing into ~ needs the owner's say-so. Three options with different refresh obligations. Filed because closing feature-t-fpc-probe-needs-a-trunk-oracle with item 3 undone would otherwise lose it."
---

# Where does a persistent FPC trunk oracle live, if anywhere?

- **Type:** decide — **Track U**. Opened 2026-08-26 by Track T, on resolving
  [[feature-t-fpc-probe-needs-a-trunk-oracle]].
- **Why it is here and not in T's queue:** the answer installs something into
  `~`, and that permission is the owner's. A coordinator dispatch is not owner
  authority, so T stopped at the repo boundary rather than guessing.

## What is already done, so this is not blocking anything

`tools/fpc_diff_probe.sh` takes `FPC=` / `FPC_TRUNK=` (each a full command line)
and classifies divergences three ways when a trunk oracle is supplied. **The
manual recipe works today** and captures most of the value on its own — the
ticket's own priority calibration says exactly that. This decision is about
whether the oracle stops being a thing someone rebuilds by hand.

## The fork

**A. Nothing persistent.** Keep the recipe in the ticket; whoever needs a
three-way verdict spends ~4 minutes building trunk into a scratch dir. Costs
nothing, and the expected yield is genuinely low — *"finding bugs in FPC is
quite rare"* (owner, 2026-08-16). The cost is that the classification is
available only to someone who already suspects they need it, which is the
opposite of when it helps: both false divergences were found by someone who did
**not** suspect the oracle.

**B. A build under `~` (e.g. `~/src/fpc-trunk`), refreshed on request.** What
the ticket sketched. Needs the owner's permission for the location, and carries
a standing obligation the ticket itself warns about: *a stale trunk build
reintroduces this problem one release later*. Trades one aging oracle for
another that ages more slowly.

**C. Build it on demand, cache it in the repo's ignored scratch.** No `~`, no
permission question, self-refreshing if keyed to the upstream tip. Costs ~1GB
of working tree and ~4 min on a cache miss, and needs a rule for when the cache
is stale. This is the option T would take if the choice were T's, because it has
no standing obligation and no owner-owned filesystem.

## What the owner is actually being asked

1. May anything be installed under `~` for this? (If no, C is the only option
   above A.)
2. Is the once-or-twice-a-year case worth any standing cost at all, or is A the
   honest answer given the stated yield?

**Recommendation: C if a persistent oracle is wanted, A if the yield estimate
still holds.** T's view is that the yield estimate is probably right and A is
defensible — but note the asymmetry that makes it a real question: the two
findings this would have caught were both found by someone who did not know to
look, and A only helps someone who does.

## Not to be confused with

The same permission question is open for a FreeBSD image (Track T,
`feature-t-freebsd-image-and-runner`). The coordinator is raising both with the
owner together so one answer covers the boundary for both; this ticket records
the FPC half so it survives its parent being resolved.

## RULED 2026-09-01 — option B, with a helper script

The owner: *"answer is - option B. and updating source and building could be a
small helper script.. having said that, it's quite rare that we test against a
nightly build."*

`~` is granted for this. The oracle lives at **`~/src/fpc-trunk`**, and
**`tools/fpc_trunk.sh`** is the refresh.

**The helper is what answers option B's stated objection.** This ticket warned
that B *"carries a standing obligation — a stale trunk build reintroduces this
problem one release later."* It does not, once refreshing is one command: the
obligation was never the staleness, it was the four minutes of remembering how.
`--check` reports how many commits behind the tip it is and exits 2, so
staleness is a question anyone can ask in a second.

**Refresh stays MANUAL, and that is the ruling rather than a shortcut.** The
owner's *"quite rare that we test against a nightly build"* is the same yield
estimate the ticket cites from 2026-08-16, and CLAUDE.md forbids timed
callbacks outright. Nothing in the script schedules itself, and nothing should
be added that does.

### The recipe above is stale in one line, found while encoding it

It says *"`~/src/fpc-source` is the user's checkout, detached at
`release_3_2_2`. Clone **from** it."* **It does not exist — `~/src` did not
exist at all on 2026-09-01.** The script clones from the mirror when it is
there (`-s`, fast, never moves its HEAD) and shallow-clones from GitLab when it
is not. A comment in the script says so, so nobody restores the line by reading
this ticket.

### Two positive controls, because a build script that cannot fail is not a gate

1. **The built compiler must not report 3.2.2.** That is the seed's version, and
   a trunk build answering it means the seed was used and nothing new exists.
2. **It must compile AND RUN a program printing 42.** This is the only thing
   that catches trap 1 — `make -C rtl FPC=` builds the RTL with the installed
   compiler and says OK, and the failure surfaces as `PPU Invalid Version 207
   expecting 208` at USE time, far from the build.

### Not done

The FreeBSD image (`feature-t-freebsd-image-and-runner`) is the other half of
the same `~` permission question and is **not** covered by this ruling. It was
raised alongside; it needs its own answer.

## Log
- 2026-09-01 — decided, commit b6f5013cc.

## TRAP 4 — found by running the recipe, not by reading it

The recipe above is **incomplete**, and its failure mode is trap 1's symptom, so
it sends you to the one thing you already got right.

`make -C compiler ppcx64 FPC=<seed>` **builds the RTL with the seed**, because
it needs an RTL to compile the compiler with. Those units are then newer than
their sources, so the recipe's next line — `make -C rtl PP=<new>` — is a make
**NO-OP**: it prints nothing, exits 0, and leaves seed-built units in place. At
use time you get `PPU Invalid Version 207 expecting 208`, which is exactly what
trap 1 says happens when you pass `FPC=` instead of `PP=`. So the reader checks
`PP=`, finds it correct, and has nothing left to look at.

**`make -C rtl clean` before the RTL build is the fix.** It is now in
`tools/fpc_trunk.sh` with the reason beside it.

This is the make-no-op family CLAUDE.md already names for the self-host seed:
*"a seeded tree (`cp` stamps a newer mtime, so `make` no-ops and exits 0)"*. The
same shape, in someone else's build system.

## Verified, and how

- **Built from nothing**: shallow clone from GitLab, compiler, RTL, ~30s after
  the clone. FPC **3.3.1**, tip `0e22f63079` (2026-09-01).
- **Runs**: compiles and EXECUTES a program printing 42. Not "compiles" — the
  PPU mismatch compiles-and-fails at unit load, so the run is the test.
- **Both positive controls exercised, not assumed.** Control 2 (compile AND run)
  fired for real against seed-built units. Control 1 (reject a compiler
  reporting the seed's 3.2.2) was exercised against `/usr/bin/ppcx64`, which it
  rejects.
- **All three modes**: default, `--check` (CURRENT, exit 0), `--path`.

**One control was wrong on first write and reported FAIL on a good build**: it
captured the compile with `2>&1` and compared the compiler's banner plus `42`
against `42`. Correct about the combined output, wrong about the question. Fixed
by separating the compile from the run; the reason is a comment in the script.
