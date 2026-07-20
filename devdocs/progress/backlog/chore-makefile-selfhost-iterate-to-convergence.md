---
prio: 45
---

# `make compiler/pascal26` demands one-pass convergence; a stale seed then fails a gate that would pass

- **Type:** chore (build rule / self-host gate consistency). **Track A**
  (`Makefile`, self-host gate). Filed by Track T — T owns the tool, not the bug.
- **Found:** 2026-07-20, while recovering a dev checkout that could not build.

## What
The `$(COMPILER)` rule builds once, verifies once, and `cmp`s:

```make
./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(BUILD_COMPILER)
$(BUILD_COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(VERIFY_COMPILER)
cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
```

That demands the fixedpoint be reached in ONE pass from whatever local seed
happens to be on disk. `tools/selfhost_fixedpoint.sh` says in its own header
comment that this is the wrong demand:

> Note it is NOT "one pass from whatever seed you had". A stale seed
> legitimately needs an extra round (stage2 came from the OLD compiler, stage3
> from the new one) — demanding one pass is what made a normal bootstrap look
> like a failure.

`testmgr` agrees and iterates ("seed is stale for these sources (one-pass
fixedpoint failed) — iterating the bootstrap to convergence"). The Makefile is
the last place still enforcing the stricter rule.

## Observed
Seeding `compiler/pascal26` from the committed pinned stable and running
`make compiler/pascal26`:

```
cmp /tmp/pascal26-build /tmp/pascal26-verify
/tmp/pascal26-build /tmp/pascal26-verify differ: byte 97, line 1
make: *** [Makefile:80: compiler/pascal26] Error 1
```

while the actual gate passes on the same tree:

```
converged after 2 round(s) from pinned: the compiler reproduces itself
agrees with compiler/pascal26 (the binary the suite is testing with)
```

Manual iteration confirms convergence at round 2 (`a26 != b26`,
`b26 == c26 == d26`), i.e. the sources are fine and the seed just needed one
more round.

## Suggested fix
Iterate to a fixedpoint up to `MAX_ROUNDS` (as the script and testmgr do) and
fail only if it has not converged by then. **Do not weaken the property** — a
fixedpoint must still be required; only the "in exactly one pass from an
arbitrary seed" part is wrong. Keeping the two definitions in sync matters
because this rule is the most important invariant in the project and a
false failure here reads as a broken box.

## Note
Low prio: the workaround (reseed from `pinned`, let it iterate) is easy once
known, and the gate itself is correct. This is about the build rule and the
gate script disagreeing, which costs whoever hits it an hour of confusion.
