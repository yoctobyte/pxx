---
prio: 70
track: C
status: done
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstatic_same_module_dup.c red at 99dcac2a2ade (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T15:30:27Z
- **Test source:** test/cstatic_same_module_dup.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cstatic_same_module_dup.c'` at 99dcac2a2ade0352ceb8fe8fc8aadbc2071ca422

## Range
bad `99dcac2a2ade`, last good `de2de369ea6a`, 11 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause found and fixed — 2026-08-21 (agent-A)

Real, reproducible at HEAD, and self-inflicted: `fa()` printed **11** instead of
2, so the program said `11 11` where the Makefile row wants `2 11`. The
duplicate-definition warning still fired — only the BINDING moved.

**Cause: `CallFix` stopped meaning "unresolved forward reference".** The DCE
work (`8cc9666fc`, in this ticket's own range) made `EmitCallProc` call
`RecordInternalCall` for **every** internal direct call, not just the forward
ones, because a body cannot be relocated unless every site that names it is
listed. That was right for DCE and quietly wrong for everything else:
`ApplyCallFixups` re-resolves each listed site from `Procs[ProcIdx].BodyAddr`,
and that row is **not immutable**. A C file with two same-named file-scope
statics compiles both bodies and the later one overwrites the row — so calls
that had already been emitted against the FIRST body were re-aimed at the
second. `fa()`, written between the two definitions, is exactly that call.

This is the only construct in the tree where a proc row's `BodyAddr` is
overwritten after a call has been emitted against it, which is why one C test
caught it and nothing else did.

**Fix: remember what each site was aimed at.** New `CallFixTarget`, parallel to
`CallFix` (a separate array, not a third record field, so the static
`ProcAddrFix`/`IramCallFix` arrays do not grow by a third for a field neither
uses). `RecordInternalCall` snapshots `Procs[procIdx].BodyAddr` — `-1` for a
genuine forward reference, an address for a site already bound.
`ApplyCallFixups` patches to the snapshot when there is one and resolves
through the proc row only when there is not, which is precisely the pre-DCE
behaviour with the DCE list intact. DCE's compaction remaps the snapshot
through `DceNewOff` exactly as it remaps the site: both are code offsets and
both move with the code.

The first body survives DCE for free — it is not any proc row's `BodyAddr` any
more, so `DceOwnerOf` answers -1 (always-live region) for its bytes.

**Verified:** `2 11` again, with the warning still firing exactly once, and
`cstatic_two_modules.c` still warning zero times and printing its five lines.
Same `2 11` under `--dce`, under `-O3` (which implies `--dce`), and cross-built
for aarch64 / arm32 / riscv32 / i386 under qemu — ApplyCallFixups has a
per-arch patch arm and every one of them was reading the mutable row.
A `--dce`-built compiler still emits byte-identical output for the whole
compiler source.

Gate: `make compiler/pascal26` + `tools/gate.sh quick` GREEN.
- 2026-08-21 — resolved, commit PENDING-COMMIT.
