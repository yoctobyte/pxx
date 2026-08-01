---
summary: "A test run should snapshot the compiler binary into its own scratch dir at start and run against that copy, so a concurrent rebuild cannot swap the binary out mid-run"
type: feature
track: T
prio: 70
---

# Snapshot the compiler into the run's scratch dir instead of running the shared path

- **Type:** feature (Track T infra, removes a whole race class) — **Track T**
- **Opened:** 2026-08-01. Filed from A+P+C+N; `tools/testmgr.py` / `tools/gate.sh`
  are Track T's files.

## The problem, from a real incident

`COMPILER := compiler/pascal26` (Makefile line 14) is a single mutable path, and
it is a **prerequisite of every test target**. So any make invocation can
rebuild it — including ones whose purpose is unrelated:

```make
pxx-debug: $(COMPILER)
	$(COMPILER) -g $(COMPILER_SRC) $(COMPILER)-debug
```

Observed 2026-08-01: a `make pxx-debug` (wanted only for a gdb build) saw a
freshly edited `.inc`, rebuilt `compiler/pascal26` as its prerequisite, and
replaced the binary **while a `make test-nilpy` was 9 minutes into using it**.
Earlier tests in that run had used the old binary, later ones the new. The run
was discarded and re-run; nothing was reported from it. It would have been
equally easy not to notice.

Note this is not the agent forgetting to be careful — the binary is a shared
mutable resource and the test run holds no claim on it.

## Fix

At run start, copy (or hardlink, then it is nearly free) `compiler/pascal26`
into the run's own scratch dir and run every job against **that** path.
`tools/testmgr.py` already creates a per-run scratch dir keyed by pid
(`/tmp/testmgr-scratch-%d`, line ~367) and already tears it down, so the
plumbing exists — this is choosing the binary path from it rather than from the
repo.

Effects:

- A concurrent rebuild becomes structurally harmless rather than a discipline
  problem.
- Provenance becomes exact for free: the run owns the bytes it tested, so
  "which binary produced this result" stops being inferred from timestamps.
- It composes with [[bug-t-run-must-invalidate-when-compiler-changes-mid-run]],
  which is the backstop for the cases a snapshot cannot cover (e.g. a run that
  legitimately rebuilds partway).

A hardlink is preferable to a copy where the filesystem allows it: rebuilds
write a NEW inode (`mv` into place) rather than truncating, so the link keeps
the old bytes alive. Confirm the build actually renames rather than writing in
place before relying on that — if it truncates, a copy is required and a reader
can currently see a half-written binary or hit ETXTBSY.

## Gate

Start a full-tier run; midway, rebuild `compiler/pascal26` from a different
source state. The run completes with every job attributed to the snapshot, and
the result is identical to the same run with no concurrent rebuild.

---

## DONE — `a31aaffeb` (claude@xeon, 2026-08-01)

testmgr copies `compiler/pascal26` into the run's scratch at start and rewrites
the **1489** recipe invocations to that path. Falls back to the repo path if the
snapshot cannot be taken — a missing snapshot must never fail a run.

### The hardlink preference does not hold on this box — measured

> A hardlink is preferable to a copy where the filesystem allows it… Confirm the
> build actually renames rather than writing in place before relying on that.

Confirmed, and it **does not rename**:

```
inode before rebuild : 270865
inode after  rebuild : 270865      # a real rebuild — it converged and wrote a new binary
/tmp  ->  tmpfs
.     ->  /dev/sdb3 ext4
```

`mv $(BUILD_COMPILER) $(COMPILER)` crosses tmpfs → ext4, so coreutils cannot
rename and falls back to copy+unlink, **writing the existing destination inode
in place**. A hardlink would have tracked the rebuild rather than pinning the old
bytes — the exact opposite of the intent. So: a copy, deliberately.

This also confirms the ticket's conditional warning unconditionally for this
box: because the destination is overwritten in place, a concurrent reader **can**
observe a half-written compiler.

### Gate

> Start a full-tier run; midway, rebuild `compiler/pascal26` from a different
> source state. The run completes with every job attributed to the snapshot.

Raced with something stronger than a rebuild — `compiler/pascal26` was replaced
mid-run by a stub that `exit 9`s, which would have failed every subsequent job:

```
testmgr: compiler snapshot /tmp/testmgr-scratch-2905992/pascal26 (sha256 f376298358bd)
testmgr: NOTE compiler/pascal26 changed during this run (f376298358bd -> 94862798bf9d)
         — jobs ran against the snapshot, results stand
testmgr: GREEN
```

Provenance also comes free, as predicted: the report now carries
`compiler_sha256`, so a result names the binary it came from instead of it being
inferred from timestamps.

## Log
- 2026-08-01 — resolved, commit a31aaffeb.
