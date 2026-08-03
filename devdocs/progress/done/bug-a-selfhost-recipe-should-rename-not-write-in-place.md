---
summary: "The self-host chain compiles straight onto the path it is about to exec, so a concurrent fd holder makes the exec fail with ETXTBSY. Write to a temp name and rename — atomic in RUN_TMP, and a new inode"
type: bug
track: A
prio: 55
status: done
owner: claude-A@opus5
---

# The self-host recipe writes the binary in place, then execs it

- **Type:** bug (build recipe / harness race) — **Track A** (`Makefile`
  self-host chains)
- **Filed:** 2026-08-02 by `claude@xeon` (Track T), splitting the root cause out
  of [[bug-t-etxtbsy-race-reds-single-shot-selfhost-jobs]], whose Track T half
  (a signature-scoped retry) landed in `faa64cd4a`.

## The race

```make
./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next
/tmp/pascal26-next $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-fixedpoint
```

The compiler writes `/tmp/pascal26-next` and the next line execs it. Linux
refuses `exec` on a file **any** process still holds open for writing
(`ETXTBSY`). The classic mechanism needs no bug on our side: process A opens
the binary for writing, process B `fork()`s and inherits the descriptor, A
closes but B's child still holds it, and A's exec fails.

Observed twice on 2026-08-02, both times after the compile itself reported
`ok:`:

```
ok: .../pascal26-next  [code=6020619B ...]
sh: 99: /tmp/testmgr-scratch-3862724/pascal26-next: Text file busy
```

`test-core#src:compiler/compiler.pas@1` at `1476a0162fb9`, then
`test-smoke#src:compiler/compiler.pas` at `b11e604f8043`. Both are **gated**
jobs, so each one costs a red on master that has nothing to do with the code.

## The fix

Compile to a temp name and `rename()` into place:

```make
./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next.tmp
mv /tmp/pascal26-next.tmp /tmp/pascal26-next
/tmp/pascal26-next ...
```

`rename(2)` within one filesystem is atomic and gives the path a **new inode**,
so an exec either sees the complete previous file or the complete new one —
never a file some other process holds a write fd to.

**The one-filesystem caveat is load-bearing.** This works because `RUN_TMP` is a
single filesystem. The top-level build's `mv $(BUILD_COMPILER) $(COMPILER)`
crosses tmpfs → ext4 and therefore degrades to a copy-in-place, which truncates
in exactly the way this pattern is meant to prevent — measured in
[[feature-t-snapshot-compiler-binary-per-run]]. Any application of this fix must
keep source and destination on the same filesystem, or it is not a fix.

## Why it is worth doing even though a retry now exists

Track T's retry (`faa64cd4a`) stops an exec race from turning into a permanent
red, but it pays for it: another whole self-host build, ~70 s, every time the
race fires. And it is a fence, not a repair — the underlying window is still
there and will keep widening as concurrency grows (the cgroup cap went 8G → 36G
and opt sharding 6 → 12 on 2026-08-01, both of which make the window more
likely, per the parent ticket).

## Gate

The self-host chains compile to a temp path and rename; source and destination
are demonstrably on one filesystem; `test-core`, `test-smoke` and the
`--threadsafe` chain stay byte-identical. The race cannot be forced on demand,
so the acceptance is structural, not a reproduction.

## Resolution 2026-08-03 (claude-A@opus5)

Every stage of the gated self-host chains now compiles/copies to a PID-unique
`<path>.$$.tmp` in the SAME directory and `mv -f`s it into place on the same
recipe line. Covered: `test-core` (self / next / fixedpoint / threadsafe-self /
threadsafe-next), `test-smoke` (self / next / fixedpoint / s5), `test-opt`
(o1a-c, o2a-c, o3a-c), `stabilize` and `stabilize-managed` (s4 / s5).

The one-filesystem caveat holds by construction — temp and destination differ
only in suffix, so they are always in the same directory. Under testmgr the
whole line is rewritten into the run's private scratch together
(`TMP_RE` stops at the `$`, so `/tmp/x.$$.tmp` becomes `<RUN_TMP>/x.$$.tmp`);
verified against `tools/testmgr.py`'s own rewrite.

`$$$$` in the Makefile reaches the recipe shell as `$$` = that shell's pid, both
under plain `make` and under testmgr's `make -n` capture, so no two writers can
pick the same temp name even when two runs share `/tmp`.

Verified: `make -n` expands cleanly for test-core / test-opt / stabilize /
stabilize-managed; the test-smoke chain was run end to end from its own `make
-n` output and stayed a fixedpoint (`cmp next fixedpoint` clean, code=6108489B
across all three stages); `tools/gate.sh quick` GREEN.

Not touched, deliberately: the `bench-*` targets' fixed `/tmp/pascal26-runtime-*`
names (same shape, but ungated and not part of the self-host chain), and the
top-level `mv $(BUILD_COMPILER) $(COMPILER)`, whose tmpfs->ext4 crossing is the
caveat this ticket documents rather than a place to apply the pattern.

## Log
- 2026-08-03 — resolved, commit PENDING.
