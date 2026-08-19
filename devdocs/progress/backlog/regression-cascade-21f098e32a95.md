---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 13 jobs newly red in 9bfb7fcfa..21f098e32 (261 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 13 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-19T17:28:45Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Range
> **The named sha `21f098e32a95` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `21f098e32a95`, last good `9bfb7fcfac03`, **261 commit(s) in range** (63 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `e6a14039a928` feat(C): the rest of the gcc bit builtins, and the `l` row that was missing
- `685504b9f496` fix(F): the charter claimed a filter that parking makes impossible
- `29db7fba05c0` feat(T): Track F is real in the tooling — F survives normalization, float/ loads, nothing 
- `da53bbd26450` feat(A): omit any of eight more frontends -- BASIC, Ada, LOLCODE, Fortran, ALGOL, Erlang, 
- `e2449adc51b7` feat(T): shape 2 — an aborted run costs the work it had LEFT, not what it had done
- `cc20f7101bf6` chore(stable): pin v365 -- the import rule with its tests and examples rewritten
- `323767360e31` docs(A)+fix: the tk criterion is purpose, not stdlib membership
- `3300c32f7fe4` feat(A): PXX_NO_AARCH64 — omit the aarch64 backend at build time
- `12fbbdf8cb8e` fix(E,B): the two examples that really did import a Pascal unit as Python
- `d7969b0f2ad9` feat(C): variable-length arrays, lowered through alloca
- `546771cbe806` feat(T): shape 4 — an unfinishable idle phase yields the slot instead of holding it
- `047bb8cc3db1` fix(A): tkinter belongs on the Python-serving unit list
- ...and 51 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 21f098e32a95be73bdeae3832aedfe65677292f7

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `lib-test#src:test/lib_mimic_xml_etree_elementtree.npy`
- `test-nilpy#src:test/test_cpyext_args_errors.npy`
- `test-nilpy#src:test/test_cpyext_containers.npy`
- `test-nilpy#src:test/test_cpyext_cython.npy`
- `test-nilpy#src:test/test_cpyext_errformat.npy`
- `test-nilpy#src:test/test_cpyext_hello.npy`
- `test-nilpy#src:test/test_cpyext_markupsafe.npy`
- `test-nilpy#src:test/test_nilpy_callable_to_str_param_fails.npy`
- `test-nilpy#src:test/test_nilpy_kwarg_overload_set.npy`
- `test-nilpy#src:test/test_nilpy_qualified_proc_omitted_default.npy`
- `test-nilpy#src:test/test_nilpy_tobject_member_via_local.npy`
- `test-riscv32#src:test/test_cross_float.pas`
- `tools-devtest#00`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
