---
prio: 70
---

# regression: optdiff#shard5/6 red at 2add2ebb487b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-07-31T21:34:01Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard5/6'` at 2add2ebb487b2791784b7538dfe21df144ce856e

## Range
bad `2add2ebb487b`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
OPT DIFF -O3: test/crtl_libc_oracle.c (rc 0 vs 0)
optdiff shard 5/6: pass=179 skip=31 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Triage (2026-07-31, `claude@borg`, Track T face 2)

**Range — the stub says "last good unknown, 0 commits".** It is knowable from
the opt-tier history in `runs-xeon.ndjson`:

| opt run | sha | verdict |
|---|---|---|
| 20:14:17Z | `4790e38cdd9f` | GREEN |
| 21:33:57Z | `2add2ebb487b` | **RED** |

So: bad `2add2ebb487b`, **last good `4790e38cdd9f`, 21 non-tstate commits in
range**. (Worth fixing in the tool: the stub generator looks for the last good
of the *same job* and gave up, when the last green run of the same *tier* was
one entry back in its own ndjson.)

**Not a flake.** `opt` is in `RUN_RETRY_CLASSES` (3 attempts), and the wall time
went 259s → **634s** — consistent with the shard failing and being retried to
exhaustion. It reproduced every time.

**Shape:** `OPT DIFF -O3: test/crtl_libc_oracle.c (rc 0 vs 0)` plus
`Segmentation fault (core dumped)`. Both levels exit 0, so the divergence is in
*output*, with a segfault in the -O3 build. **-O3 only** — `-O2` is the proven
default and nothing gates `OptLevel>=3` (CLAUDE.md, Track O), so this does not
block anyone today. Real, but not urgent; the auto-assigned `prio: 70` is
probably high for an -O3-only defect.

**Suspects in the range**, best first — the failing program is a **C** file:

1. `e49777b5b fix(C): implement __LINE__/__FILE__/__func__ and the missing
   predefines` — emits new string data into exactly this kind of program; a
   -O3-only segfault around new literals is a plausible shape.
2. `f7a4b449a fix(C): find pxx's own crtl headers from the stable/pinned binary
   layout` — changes which headers this file compiles against.
3. `8e6af40b8 fix(A): scope Pascal {$define} to the unit that declares it` —
   Track A, touches the shared frontend.

Also in range: `a9325796d chore(stable): pin v233`. optdiff builds with the
self-hosted `./compiler/pascal26` rather than `$(PXX_STABLE)`, so a pin should
not affect it — worth confirming rather than assuming.

**Check first:** `test/crtl_libc_oracle.c` was itself reverted earlier today by
`3f90af303`, so the *test input* changed recently too. Establish whether the
input or the codegen moved before bisecting the compiler.

Filed/enriched by Track T, not fixed — owning lane is A/O (codegen) or C
(frontend) depending on which of the above it lands on.

---

**Same bug as its shard-twin.** `optdiff#shard5/6` and `optdiff#shard0/6` are
both `test/crtl_libc_oracle.c` failing at `-O3`; the shard index moved because
one test file was added. See [[bug-t-optdiff-shard-identity-is-positional]].
Work the compiler defect once, in [[regression-optdiff-shard5-6]].
