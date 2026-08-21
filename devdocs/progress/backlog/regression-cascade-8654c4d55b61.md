---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 11 jobs newly red in 4f526e338..8654c4d55 (241 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 11 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-21T10:19:04Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Range
> **The named sha `8654c4d55b61` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `8654c4d55b61`, last good `4f526e338205`, **241 commit(s) in range** (16 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `b8ce37d5bfc4` chore(stable): pin v369
- `ef895b743c14` feat(A): emitted nil checks on method-call receivers
- `a90ad49efdb2` fix(A): `OnClick := nil` segfaulted at the store
- `97b1812fece0` feat(A): a nil procvar call is catchable now, on every target
- `3bf6f623fa95` test(P): a helper's const is not a global — the test was asserting the leak
- `59cddd3b7780` fix(A): a unit's {$mode} turned delphi mode off for the whole program
- `09aaae653d25` fix(A): line numbers after an {$I} include named no line of any file
- `0e452e1aa16a` fix(A): AIntToStr('-5') was '', not '-5'
- `8f851204d193` refactor(A): the last three copies of "is this an ESP-class target?"
- `15db37e627b5` feat(A): Copy() on a nested dynamic array
- `bda942a0b02d` feat(A): --mimic-fpc-compiler — the FPC-compiler build-config define profile
- `8b2d2d7c5c40` fix(A): sigaltstack + SA_ONSTACK on i386, arm32 and aarch64
- ...and 4 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 8654c4d55b61605fc5dea51a38887e713d5b9fc0

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-asm#src:compiler/compiler.pas`
- `test-core#src:test/test_rust_advanced.rs`
- `test-core#src:test/test_rust_assoc_fns.rs`
- `test-core#src:test/test_rust_chess_engine.rs`
- `test-core#src:test/test_rust_chess_perft.rs`
- `test-core#src:test/test_rust_chess_perft_full.rs`
- `test-core#src:test/test_rust_chess_search.rs`
- `test-core#src:test/test_rust_else_if.rs@1`
- `test-core#src:test/test_rust_else_if.rs@2`
- `test-core#src:test/test_rust_struct_array.rs`
- `test-core#src:test/test_rust_tuple_struct.rs`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
