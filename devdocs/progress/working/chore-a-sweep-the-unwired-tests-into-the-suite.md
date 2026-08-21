---
track: A
prio: 55
type: chore
owner: agent-A
blocked-by: []
summary: "DECIDED 2026-08-19: SWEEP the ~61 unwired test files into the suite — one job, not 61 tickets. Track A, not T, precisely because A can FIX a red in place; T would have had to file one per red. These are repro tests from fix commits that were never wired, so the bug already has a ticket in done/ — reference it, do not re-file. Never record current output as the expectation."
status: working
---

# Sweep the unwired tests into the suite

**Implements [[decide-what-an-unwired-test-may-assert]]** (user, 2026-08-19).

## Track A, and the lane choice is the whole design

This was first filed under Track T — test infrastructure, T owns the wiring tool, T did
the original triage. **The user rejected that, and the reasoning is the important part:**

> "It may lead to a waterfall of tickets. So if Track T is the wrong choice, make it
> Track A. And just sweep it — not a new ticket for everything that was already ticketed
> and fixed."

T is bound by *"T owns the tool, never the bug"*, so under T **every red must become a
ticket for another lane**. With ~61 files that is a ticket factory, and the handoff cost
would exceed the work. **Track A can fix a red in place**, so the same job is a *sweep*:
one unit of work, a handful of commits.

**Consequence: this is one job with one owner, not 61 items.** Do not decompose it into a
ticket per file.

## What the files are — measured, and it sets the method

`tools/check_test_wiring.py` found 98 test files no build rule runs; 10 are now wired. Of
the remaining 85: **61 compile today**, 5 are helper modules correctly not rules, ~5 need
particular flags, ~10 are blocked by a compiler error.

**Every one of the 30 most recent commits that added a file under `test/` is a `fix(...)`
or `feat(...)`.** They are repro tests written alongside real bug fixes and never wired —
an omission at the last step, not a judgement of worth.

## Method

1. Find the adding commit: `git log --diff-filter=A -- <file>`.
2. **Fix/feat commit** → wire the test to assert the behaviour that commit describes, and
   **write the commit sha into the expected file** so the provenance is visible rather
   than lost.
3. **No fix commit, no ticket, no discernible intent** → genuine leftover, delete it.
4. **Commit does not say what the right output is** → use the reference oracle
   (`tools/fpc_diff_probe.sh`, `gcc_diff_probe.sh`, `pydiff.py`). If that is not
   conclusive either, park the file and move on — do not guess and do not stall the sweep.
5. Where the source is legal input to the reference implementation, prefer the
   **dual-runnable** form (`test/lib_mimic_warnings.npy`): valid CPython *and* valid
   NilPy, asserting only the subset both agree on, so the oracle is a property of the file
   rather than a step that expires. Natural for NilPy, plausible for C, not for Pascal.
6. **Assert a COUNT as well as the content** — otherwise a test that silently stops
   emitting half its assertions still passes.

## Tickets: reference, do not re-file

**The bug already has a ticket, and it is in `done/`.** These files were created by fix
commits, so a red means either a regression of something already recorded, or a test that
was never quite right. Neither needs a new ticket in the ordinary case.

- **Red you can fix** → fix it in the sweep. No ticket.
- **Red that is a regression of a known bug** → **reference the original ticket** (the
  adding commit names it); do not open a duplicate.
- **File a new ticket ONLY** for something genuinely new, genuinely deep, and out of scope
  for the sweep — and then park that file rather than letting it hold up the rest.

**Grep `done/` before filing anything.** A resolved ticket re-filed as new work is a
documented recurring failure here.

## The one rule that does not bend

**Never record current output as the expectation.** A test built that way cannot fail for
the reason tests exist — it detects *change*, not *wrongness*, and defends a bug as
loyally as a correct value. If the right answer is unknown and the oracle cannot settle
it, park the file (step 4). Parking is cheap; a false expectation with a green tick in
front of it is not.

## Practical

- Wiring edits the **Makefile**. A owns it, so no cross-lane collision — but keep the
  batch coherent rather than dribbling edits across days.
- Gate as normal for A: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
  + `tools/gate.sh quick`. The newly wired tests then ride Track T's matrix from the
  pushed sha onward, which is the actual payoff.
- **Sample caveat:** the 30 sampled additions are recent work. Sample the older tail
  first — if those are scruffier, step 3 (delete) applies more often than assumed.


---

## Batch 1 — 2026-08-19 (frankonpiler-an). 85 -> 61 unwired.

Sweep in progress, not finished. This batch is deliberately the part that could
be settled by an ORACLE rather than by judgement.

### Measured first: the ticket's sample caveat was right

The ticket sampled the 30 most recent additions and found every one a
`fix`/`feat`. Over the WHOLE set: 65 of 85 are `fix`/`feat`, and the other 20 are
older and scruffier — helper units, manual inventories, external-dependency
probes. So the "sample the older tail first" caveat held, and that tail is where
the non-tests live.

### 15 exemptions (test/UNWIRED.txt), each verified

- **8 consumed by a WIRED test** — helper units and included C files. Verified in
  both directions: the file really is named by the consumer, and the consumer
  really is in the Makefile.
- **4 `test/manual/**`** — a Synapse compile inventory driven by
  `test/manual/try_synapse_compile.sh`, needing a checkout this repo does not vendor.
- **3 `test/gamelib/*_probe.*`** — need cglm / enet / ZenGL headers.

### 9 wired (C)

`carray_field_decay_ptr_b120`, `cbitfield_longlong_b359`,
`cbitfield_promotion_b358`, `cfloat_global_array_implicit_len_b386`,
`cglobal_double_init_arith_b353`, `cint_mod_unsigned_b360`,
`cnested_struct_deep_redef_b354`, `cptr_field_index_stride_b121`,
`cptr_field_typedef_forward_stride_b121`.

These are the ideal shape: **self-asserting** (`return 42` on success, a distinct
code per failed check), so the expectation lives in the file rather than in a
recording. Each was additionally **built and run under gcc** before wiring — all
nine return 42 under both. That satisfies the rule that does not bend, and it is
step 5's dual-runnable form: the oracle is a property of the file, not a step
that expires.

Wiring verified by `make -n compiler/pascal26` (Makefile parses, without going
near the suite) plus running all nine wired lines verbatim.

## Two findings for Track T — the checker, not the bug

`tools/check_test_wiring.py` is T's file so I did not touch it. Both are
false-POSITIVE directions (it over-reports), which is the safe direction, but
they cost sweep time:

1. **A bare name in a Makefile `for` list is not seen.** `test_exc_resident_param.pas`
   is reported unwired, but the Makefile runs it at all four `-O` levels via
   `test/$$t.pas` inside a `for t in ...` list. The checker's `test/[A-Za-z0-9_./+-]+`
   pattern cannot match a name that is only concatenated at expansion time. It is
   the ONLY file in the 85 affected, so the real backlog was 84.
2. **`consumed_by` matches a `uses` clause by STEM, so the path form is missed.**
   `test/test_relpath_uses.pas` says `uses './relpath/sub/relmath', './relpath/relstr'`,
   and its three helpers were all reported unwired. Ironic given the test's own
   subject is path-form uses. Exempted here instead.

## What is left: 61, and they need judgement, not an oracle

56 `.pas` + 5 `.c`. The remaining Pascal ones are largely compiler-internal
(`test_x64enc`, `test_asm_emit_*`, `test_pyeval_*`, `test_residency_*`) which FPC
cannot build, so `fpc_diff_probe.sh` is not available as the oracle and each needs
its adding commit read for what the right answer IS. That is the slower half and
the one where step 4 (park rather than guess) will actually bite. Left claimed.


## PARKED 2026-08-19 mid-sweep (frankonpiler-an)

Batch 1 landed (`972162790`, 85 -> 61). Parking rather than holding the lock:
switching to `feature-n-a-callable-value-carries-its-signature-type` (p88),
which outranks this, and an idle worker sitting in `working/` misreports the
claim.

**Resumable with no re-derivation.** The remaining 61 (56 `.pas`, 5 `.c`) are the
judgement half: mostly compiler-internal Pascal (`test_x64enc`, `test_asm_emit_*`,
`test_pyeval_*`, `test_residency_*`) that FPC cannot build, so
`fpc_diff_probe.sh` is NOT available as the oracle and each needs its adding
commit read for what the right answer is. Expect step 4 (park the file, do not
guess) to bite here in a way it never did in batch 1. Whoever resumes: the
oracle-settled work is already done, so do not go looking for more of it.


---

## Batch 2 — 2026-08-21 (agent-A). 65 -> 55 unwired.

Batch 1 left 65. This batch takes the **-O3 optimisation repro tests**, which
are coherent as a group for the reason that makes them wirable: each one's own
header says *"output must be identical at every -O level"*, so the file carries
a property, not just a recording.

All ten go into **`test-core`**, which is in the watcher's `native` tier — so
from the pushed sha onward they run on every sweep, which is the payoff.

### 6 wired with FPC 3.2.2 as the oracle (or the file's own stated rule)

`test_inline_nonleaf`, `test_inline_branch_locals`, `test_inline_depth_reentry`,
`test_residency_unified`, `test_residency_boundaries` — each compiled and run
under FPC and **byte-identical to pxx at -O0, -O1, -O2 and -O3**. Both halves
are asserted: the cross-O property AND the values, because a differential that
compares a wrong answer to the same wrong answer passes while asserting nothing.

`test_regcall_arg_order` is the one where FPC is **not** the oracle, and the
difference is a decided dialect rule rather than a defect: pxx evaluates
arguments strictly left-to-right; FPC prints `t1=6010003`, reading the global
*after* the position-2 call mutates it. ISO Pascal leaves the order unspecified,
so neither is wrong — only one is ours. Every expected value was recomputed from
the rule the file's own comments state (`t1 = 5*1000000 + 10*1000 + 3`), not
copied off a run.

`test_inline_depth_reentry` deserves its own line: it is 21 fuzz-found
miscompiles reduced to one file, guarding a splice that re-enters the expander
from an argument list. Invisible at -O0. Nothing had run it since the day it was
written.

### 4 more, same batch

- `test_promoint_bitwise` — FPC cannot compile it (`PromoInt` is ours, and FPC
  refuses to `writeln` one), but the file states every expected value in a
  trailing comment, so the expectation is the author's, transcribed.
- `test_writeln_mix` — FPC prints the same line.
- `test_rtti_field_get_by_name`, `test_rtti_method_call_by_name` — both already
  halt(1) on their own failures; the rows add the values, each derived (Base=100
  so Add(42)=142, Bump leaves 101) and each `kind=` checked against
  `compiler/defs.inc`'s `TTypeKind` rather than accepted.

### One ticket filed, deliberately

Checking those `kind=` numbers turned up
[[bug-a-rtti-kind-numbers-are-the-compilers-not-the-typinfo-enum-the-unit-documents]]:
`typinfo.pas` documents `RetKind`/`TypeKind` as `Ord(TTypeKind)` and declares
`TTypeKind` in **FPC's** order (Int64 = 19), while the compiler fills those
fields with its **own** enum (Int64 = 13) — and the unit's own `TypeKindSize`
already decodes the compiler's numbering. `if mi^.RetKind = Ord(tkInt64)` reads
as obviously correct and is silently wrong. Genuinely new, genuinely deep, out
of scope for a wiring sweep: exactly the ticket the method allows.

### Finding 3 for Track T — the checker, still not the bug

`test/csqlite_file_probe.c` is reported as a STALE exemption because
`wired_paths()` is textual over `tools/*.py`, and
`tools/testmgr_hardcoded_tmp_devtest.py:95` names the path as **test DATA** (a
table of hardcoded `/tmp` paths). A tool's own fixture table is not a build rule.
Same over-report direction as findings 1 and 2 — safe, but it costs sweep time,
and here it argues for DELETING a legitimate exemption.

Its reason line was wrong on its own terms and is corrected in this batch: the
file needs the gitignored sqlite amalgamation, like its `csqlite_*_probe`
siblings. The previous reason ("used by csqlite_parity_selfcompiled.c") was
false — that file only names it in a comment.

### Left for the next batch
The ~18 `test_esp_*` (need `--target=xtensa` and a flashing/qemu story), the 14
`test_pyeval_*`/`test_pyexec_*` (Track N deferred by the user), the 5
`test_asm_emit_*`, the 2 `test_softfloat_*` (Track F, parked by definition), and
the `csqlite_*` probes that need the amalgamation.
