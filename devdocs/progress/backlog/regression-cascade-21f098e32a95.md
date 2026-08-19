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

---

## TRIAGED 2026-08-19 by frank2-C — **four causes, not one**

Every one of the 13 was reproduced by hand at HEAD (`gate.sh quick` cannot see
any of them). The "one root cause until triage proves otherwise" rule held for
the first nine and then broke: it is four.

| # jobs | cause | routed to |
| --- | --- | --- |
| 6 | the NilPy import rule vs a **cpyext extension module** — `import hello_ext` is CPython's own spelling and is now refused | `decide-nilpy-import-rule-vs-a-cpyext-extension-module` (Track U) |
| 3 | ordinary bare-import migration missed when the rule landed | **fixed here** |
| 2 | a **callable value** silently reaching a `str` parameter, and no longer comparing equal to itself | `bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method` (N) |
| 1 | riscv32 float **formatting** width vs x86-64 | `bug-a-riscv32-cross-float-output-no-longer-matches-x86-64` (A+F) |
| 1 | `twatch_host_epoch_devtest.py`, one case | Track T — its own tooling, handed back |

### The three that are fixed

`test_nilpy_kwarg_overload_set`, `test_nilpy_qualified_proc_omitted_default`,
`test_nilpy_tobject_member_via_local` each imported a genuine Pascal unit by
bare name; migrated to the quoted spelling the rule prescribes, each verified
against its own Makefile expectation. Green.

### The six that are NOT fixed, deliberately

The cpyext tests import a **C extension module** by its bare module name —
which is what a CPython program writes, and what the whole cpyext campaign
exists to make work. Rewriting them to `import 'hello_ext.pas' as hello_ext`
would turn them green by deleting their subject. Filed as a Track U decision
instead; see the ticket for the three options.

### Two corrections to this ticket's own framing

1. **The lib-test job is not a regression in this range at all.** It builds with
   `$(PXX_STABLE)`. The pre-range pinned binary runs it GREEN; a compiler built
   from source at the range's own last-good sha `9bfb7fcfac03` fails it, and so
   does one built at `7bebd63fa`, the commit that ADDED the test. The defect was
   already in the source and the pin was lagging behind it. **`cc20f7101`
   (pin v365) EXPOSED it; nothing in the range caused it.** Any future cascade
   that straddles a pin needs this question asked before the range is read.
2. **`test_cross_float` is not `da53bbd26`.** frank3's prior was right — those
   are omission defines defaulting to OFF. The suspect is `354f734c1` (the sci
   float writer learning Single widths), argued from the shape of the change.

### The one that was bisected

The `str`-parameter refusal loss: GOOD at `9c5148087` and `e78cc5882`, BAD at
`9bbbbef6c` — five builds in a throwaway clone seeded from the pinned binary,
never in the shared checkout. Recipe is in the N ticket.

**Nothing here justifies a pin.** Three jobs are green, ten are filed and open.

---

## `tools-devtest#00` — closed 2026-08-19 by plexus-T, and it was never in this range

The 13th job is answered, and the answer changes the count: **it is five causes,
not four.** It is also not a regression in `9bfb7fcfa..21f098e32` at all.

The job's true first-bad is **`a1fd5715e`** (2026-08-19T15:44:05Z) — the commit
that *created the job*, by wiring `tools-devtest` into the Makefile and the full
tier. It has never once passed in the watcher. It is inside the range only
because the range is 261 commits wide.

**The failure the watcher saw is not the one frank2 reproduced.** The Makefile
loop stops at the first failing file, and `tstate_reader_devtest.py` sorts
before `twatch_host_epoch_devtest.py`, so in the watcher it failed first and
masked everything after it:

    FAIL detachment-is-detected: a checkout on a branch was reported as detached

That check asserted `head_detached(THIS repo) is False` — a property of the
**runner**. Every dev checkout is on a branch, so it passed in frank2's
hand-repro at HEAD and the *next* file's failure is what triage saw. A watcher
clone is detached at the sha under test by design, so in the one environment
where the full tier runs, the assertion could not hold. Fixed against a scratch
repo, both directions pinned:
`bug-t-the-detachment-guard-tests-its-own-runner-not-the-predicate`.

`twatch_host_epoch_devtest.py` — the one frank2 handed back — is **green** at
HEAD and needs nothing. It was fixed by `a1fd5715e` itself.

### What this adds to correction 1

Correction 1 above says a `$(PXX_STABLE)` straddle needs asking *"was this
exposed rather than caused"* before the range is read. This is the same question
in a third direction: **was the job even old enough to regress?** A job created
inside the range has no last-good measurement, so "newly red in this range" is
true of the *observation* and says nothing about the *code*. Track T's own
tooling is where that will keep happening, because T adds jobs.
