---
slug: decide-should-forwardlint-run-in-the-build-not-only-the-gate
track: U
prio: 55
status: open
---

# Should `forwardlint` run in `make compiler/pascal26`, not only in `gate.sh`?

**This is the owner's call because it changes the cost of the most-run command in
the repo**, and the per-fix loop is defined in CLAUDE.md. Filing rather than
deciding.

## What happened

On 2026-08-30 a lane pushed `392782317`, which added `CNodeArrayShape` and called
it ~1000 lines above its body. pxx prescans the unit; **FPC resolves in source
order**, so the bootstrap seed could not compile at all. It sat on origin for
**three commits**. `make compiler/pascal26` stayed green throughout — as it must:
the fixedpoint proves the compiler reproduces *itself*, compiled **with pxx**, and
a missing forward declaration does not disturb that. This is face 31, the seed
canary hole, doing exactly what it is documented to do.

`tools/forwardlint.py` exists precisely for this and exits 1 correctly. It did not
fire because it is wired **only into `gate.sh`** (`tools/gate.sh:221`), and
`gate.sh quick` is *optional* per fix — *"run it when you touched something you're
nervous about."* The lane ran it one commit late, on a different change, and it
caught the earlier break.

The lane's own read, which is fair: a new routine called from a distant include is
exactly the "something you're nervous about" case, so the clause worked as written
and the judgement call went the other way. **A documented trap is not a guard.**

## The fork

**A. Wire it into the `compiler/pascal26` recipe.** Closes the hole by
construction — the one class of breakage the per-fix loop is blind to *by design*
stops leaving anyone's tree.

**B. Leave it in `gate.sh` only** and rely on the optional clause plus Track T's
sweep.

**C. Something narrower** — e.g. run it only when a `.inc` gained a new
`procedure`/`function` since the last build.

## The measurement

`python3 tools/forwardlint.py` = **4.1s**. `make compiler/pascal26` = ~12s. So
option A is ~16s, a **33% increase on the repo's most-run command** — but only on
an actual rebuild, since make skips the target when sources are unchanged, and a
rebuild is exactly when the check is needed.

## Recommendation

**A.** 4 seconds on a command that already costs 12, paid only when sources
changed, against a failure mode that is invisible to the entire per-fix loop by
construction and that poisons the seed for every lane. The asymmetry is the
argument: the loop's own documentation says this hole exists and cannot be closed
from inside it, so the check has to sit outside — and `gate.sh` being optional
means "outside" currently means "sometimes".

The counter-argument deserves stating: eight lanes each paying 4s per rebuild all
night is real, and the owner may prefer C. What should **not** happen is B plus a
stronger warning, which is the option that already failed.
