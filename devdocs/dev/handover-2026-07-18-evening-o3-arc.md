# Handover 2026-07-18 evening — the -O3 arc (Track O session log)

One session, seven landings on master. Everything behind -O3 unless noted;
-O0/-O2 byte-identical to the pinned stable verified per push (x86-64 AND
aarch64). Full detail in each ticket's log; this is the map.

## Landed (chronological)

1. **cc9bfd17 — pxx internal ABI slice 1 (x86-64).** xmm8–13 callee-saved
   save-iff-used; float residency in call-bearing bodies. Three leak paths
   found and wrapped (descendant-extern, coswitch, longjmp-past-epilogues) via
   the per-body pool save area (`FxSaveOn`/`FloatPoolSave/Restore`).
2. **b804714b — unified int+float residency pass.** One tally, per-class pools;
   GPR pool widened to r12–r15 minus regcall (4 int residents max, was 2).
   4-int loop 1.35x, mixed loop 1.66x (-O3 vs -O2).
3. **588d525c — aarch64 mirror.** x19–x24 + d8–d13; AAPCS64 = no extern wraps;
   coswitch + exc-landing wraps mirror x86. Generators are x86-64-stackful-only
   (`generator; stackless;` + `uses slgen` for cross).
4. **b18ca150 — residency regression tests** (`test_residency_unified` /
   `_boundaries` / `_coswitch`) — optdiff sweeps them each tier now.
5. **258c7b8d — regcall phase 3 slice 1** (all-simple args direct into arg
   regs) **+ the main-body wild-write fix**: `FloatPoolBoundaryAssign` reserved
   frame slots in the main body (CurProc<0), which has NO PatchProcPrologue
   backing late FrameSize growth → IR_CALL_IND wrap wrote wild below rbp
   (test_frozen_string_reentrant -O3 SIGSEGV). RULE: every CompileAST-time
   frame-slot-reserving pass guards `CurProc < 0`.
6. **2dffbb7c — regcall phase 3 slice 2** (deferrable args from any position;
   addr-clean locals can't be written by sibling calls; `PaScan*` verdict
   cache). Mixed-args loop 1.17x. Semantics test `test_regcall_arg_order.pas`.
7. **div0-stub fix (last push).** Ticket premise corrected: the stub is
   load-bearing whenever builtinheap is pulled (its own early div sites,
   pre-PXXDivZero-registration, fall back to it). REAL find: **C and NilPy
   drivers never emitted the stub → latent `call 0` on early div-by-zero
   paths.** Fixed (stub emitted before RTL pulls in both drivers) + hard-error
   safety net at stub-needing sites.

## Discipline learned (cost: one shipped regression, caught in-session)

- **`make test-opt` per -O3 emission slice** — quick+self-host misses
  -O3-only breakage by construction. The main-body bug shipped through THREE
  pushes because test-opt wasn't in the loop. It is now.
- Full-tier runs test the WORKING TREE — no source edits/rebuilds mid-run.
- `stable_linux_amd64/default/pinned` is not directly executable (symlink
  chain); use `stable_linux_amd64/default/stable_pinned`. A `>/dev/null 2>&1`
  harness silently voids a check against the wrong path.
- pxx ELFs have no section headers — objdump -d is empty; byte-scan
  (python re / struct over 4-byte words) is the way to verify emission.

## Open / next (Track O queue after this session)

- **Track T**: watcher was DOWN most of the session; a clean local
  `testmgr --tier full` was launched post-div0-landing (check its result!).
  T will also sweep all seven SHAs when back.
- **-O2 promotion**: deliberately parked (user call) — -O3 carries benches.
- **Real-hw aarch64 bench** for the residency mirror (qemu timing useless).
- **Next implementation item**: inline slice 2c (branch-with-locals) — ticket
  `feature-inline-nonleaf-and-branch-locals` has the full plan; the work is
  the branch-aware assigned-before-read analysis, the splice machinery already
  handles AN_IF.
- `feature-opt-rtti-emit-on-use` (prio 40) — next size item, hits ESP too.
- Phase 4 regcall (cross caller-side) — optional per charter.
