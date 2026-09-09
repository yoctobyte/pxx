---
slug: bug-t-three-compiler-spellings-opt-out-of-the-testmgr-snapshot-silently
track: T
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frank-seven
tags: [testmgr, snapshot, harness, latent]
blocked-by: []
summary: "6aa50d6eb fixed COMPILER_PATH_RE's matches-TOO-MUCH mode (`../../compiler/pascal26` had its `..` prefix survive the rewrite). The matches-TOO-LITTLE mode is untouched and was never filed. Measured across all recipe rows naming the compiler: `./$(COMPILER)` 5717 rows rewritten correctly, `../../$(COMPILER)` 1 row now fixed, and THREE spellings still skipped -- `$(CURDIR)/$(COMPILER)` (Makefile:4119, test-nilpy), `\"$root/$(COMPILER)\"` (Makefile:28806, test-uforth), and a bare `compiler/pascal26` (Makefile:155) passed as an argument to a script. The first two SILENTLY RUN THE WORKTREE BINARY instead of the per-run snapshot. Latent rather than standing: the snapshot is a copy2 of that same binary, so they diverge only when a rebuild lands mid-run -- which is exactly the scenario the snapshot exists for, and testmgr already reports `compiler_changed_mid_run` because it happens."
---

# Why "latent" is not "harmless"

The snapshot exists so a tier's verdict names one binary. A row that opts out
reads whatever `compiler/pascal26` is at the instant it runs. On a quiet tree
that is the same file and nothing differs — which is why this has never been
seen and why a byte-comparison would not find it.

It bites precisely when a rebuild lands mid-run, and that is not hypothetical
here: `compiler_changed_mid_run` is a field testmgr publishes because the case
occurs, and the auto-pin refusal gate reads it. **The first opt-out was found in
`test-nilpy`, which is where the mid-run rebuild was first observed.** So the
two rows most likely to be affected include the one where the phenomenon was
first noticed.

# The shape of the fix

Do NOT extend the regex to match `$(CURDIR)/` and `"$root/"` by adding
alternatives — that is the third copy of the same table and it will miss the
fourth spelling the same way it missed these three. Two better directions:

1. **Make the opt-out loud.** Any recipe row naming `compiler/pascal26` that the
   rewriter does NOT touch should be reported once per run, with the line
   number. Three rows today, so the noise is bounded, and a new spelling
   announces itself instead of silently opting out. This is the cheap one and it
   converts an invisible class into a visible list.
2. **Normalise the spelling at the source.** If the rows can all say
   `./$(COMPILER)`, the rewriter needs one pattern. Check first whether
   `$(CURDIR)/` and `"$root/"` are load-bearing for the `cd` those rows do —
   `.././` was, which is how this family started.

`Makefile:155` is a third case and may be fine: the path is an ARGUMENT to a
script, not an invocation, so rewriting it might be wrong. Decide it explicitly
rather than by omission, and say which in the commit.

# Provenance

frank-seven, re-testing all five spellings against the NEW pattern after
`6aa50d6eb` landed, having established that the fix closed the too-much mode.
Not a regression from that commit — these three were skipped before it too.
