---
summary: "seed-from-stable makes the whole matrix test the pinned binary; only selfhost-fixedpoint can see it"
type: task
track: T
prio: 65
status: done
owner: claude@xeon
---

# `seed-from-stable` silently defeats the self-host rebuild

- **Type:** tooling trap (Track T — `tools/testmgr.py`)
- **Found:** 2026-07-31, enrolling the xeon watcher box. First run: 17 red.

## What happens

The documented fresh-box step is `make seed-from-stable`, which **copies**
`stable_linux_amd64/default/pinned` onto `compiler/pascal26`. The copy gets a
**fresh mtime**, newer than `compiler/compiler.pas`. testmgr then runs
`make compiler/pascal26`, make says *"up to date"*, and no self-host build ever
happens — the entire sweep tests the **pinned** binary instead of a compiler
built from the checked-out sources.

Measured on xeon at `110774a14648`: `compiler/pascal26` byte-identical to
`pinned`, mtime 13 minutes newer than the sources.

The window is not just the first run. It persists for **every sha whose diff
does not touch a compiler source** — a tstate commit, a docs commit, a
`lib/**`-only commit — because nothing bumps a source mtime past the binary.

## Why it matters

This is a concrete mechanism for the "phantom NEW-RED" complaint: jobs go red
against a stale compiler, then "fix themselves" on the next sha that happens to
touch `compiler/**` and forces a real rebuild. No commit in the range can
explain either transition, which is exactly the signature that makes other
agents stop trusting tstate.

Only `selfhost-fixedpoint` can detect it (property 2, the anti-Thompson
agreement check) — and when it does, it reads as a scary self-host regression
rather than "your seed is stale".

## What is already guarded (do not re-implement)

`twatch.run_gate()` **already knows about this** and backdates the seed:

```py
if not os.path.exists(comp):
    subprocess.run(["make", "--no-print-directory", "seed-from-stable"], ...)
    os.utime(comp, (0, 0))      # "55 false reds on the first live deploy, 2026-07-07"
```

So the daemon's own fresh-clone path is safe. The hole is everywhere else:

- the guard is under `if not os.path.exists(comp)`, so a clone that **already
  has** a binary — every clone after the first cycle — is never re-backdated;
- `tools/testmgr.py` has no such guard at all, so any **manual** run is exposed;
- the deploy documentation tells a human to run `make seed-from-stable` directly
  (`devdocs/dev/track-t.md`, `fpc-optional-workflow.md`), which is precisely how
  xeon hit it during enrollment.

The 2026-07-07 fix treated the symptom at one call site. The invariant — *never
run the matrix against a binary that is byte-identical to `pinned`* — belongs
where the matrix runs.

## Fix (Track T's own file)

`tools/testmgr.py`, at the point it builds the compiler: before trusting make's
"up to date", assert the binary is not simply the pinned seed —

- if `compiler/pascal26` is byte-identical to `stable_linux_amd64/default/pinned`,
  force the rebuild (`touch compiler/compiler.pas`, or build to a temp path and
  move it in), and say so on stdout;
- log the built binary's sha256 in the run report, so every verdict names the
  binary it came from (the repo's own "verify against a KNOWN sha" rule).

Do **not** fix this by editing the `seed-from-stable` rule — the `Makefile` is
Track A's fenced ground. The check belongs in testmgr.

## Repro

```sh
make seed-from-stable
tools/testmgr.py --tier native --job 'src:tools/selfhost_fixedpoint.sh'
# FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26
touch compiler/compiler.pas && make compiler/pascal26
tools/testmgr.py --tier native --job 'src:tools/selfhost_fixedpoint.sh'   # green
```

## Log
- 2026-08-03 (`claude@xeon`) — fixed in testmgr, as the ticket specifies: the
  invariant belongs where the matrix runs, and the `seed-from-stable` rule is
  Track A's ground and stays untouched.

  `unseed_pinned()` runs at the top of `build_compiler()`: if
  `compiler/pascal26` is byte-identical to `stable_linux_amd64/default/pinned`,
  that is the SEED, not a build, so the binary is backdated to the epoch and
  make rebuilds from source. Backdating the binary rather than touching
  `compiler/compiler.pas` on purpose — a touched source becomes newer than
  everything else and can cascade into other mtime-driven rules, whereas an
  epoch-old binary simply loses to every source, which is the ordering make
  should have seen in the first place.

  Reproduced the trap first, exactly as written: after `cp pinned
  compiler/pascal26`, `make -q compiler/pascal26` exits 0 — "up to date" — so
  the sweep would have tested the pinned binary. With the guard, testmgr says
  so and the self-host build runs (converged after 1 round); the rebuilt binary
  is byte-identical to the real one and differs from `pinned`.

  Second half of the ask done too: the tstate report's frontmatter now carries
  `compiler_sha256`. The json has had it since the mid-run-change check, but
  the markdown is what a human reads days later, and "verify against a KNOWN
  sha" is unusable if the report does not name the binary.

  `tools/testmgr_unseed_devtest.py` pins it: identical -> backdated, a real
  build -> untouched (the guard fires on identity, never on suspicion), same
  size but different bytes -> untouched, and a checkout missing either file ->
  quiet no-op rather than a crash.
- 2026-08-03 — resolved, commit 548a69518.
