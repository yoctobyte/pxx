---
track: A
prio: 40
type: chore
owner: frankwasm
blocked-by: []
summary: "DONE 2026-08-30 (frankwasm), batch 5: the general unwired-test backlog is EMPTY and top-level is zero for the first time. 6 subjects wired against oracles that were DIFFED (5 vs FPC 3.2.2 byte-for-byte, 1 vs `wc -c` of its own .data), 2 C helpers exempted because compiling them standalone would test a shape that never occurs, 1 stale exemption removed. The 37 files check_test_wiring still names are ALL test/wasm/** and are NOT orphans: they are one campaign's harness (37 slices, 38 check_*.sh, check_all.sh) whose top-level hook is missing, recorded in feature-target-wasm — do NOT open a batch 6 for them. The inflow is the unsolved half and is now frankT's: gate.sh quick asks the per-push question as of 7c1c422c9. NEVER record current output as the expectation; a file with no constructible oracle is left UNWIRED WITH A STATED REASON, which is the honest form of a skip."
status: done
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

## Batch 3 — the assembler harnesses, and the helpers that were never gaps (65 → 42)

Six subjects wired, five exempted with reasons. The two halves are different
work: the first half found **rotted harnesses**, the second found **files that
were never unwired at all**.

### The five asm harnesses had stopped compiling

`test_asm_emit_386`, `_a64`, `_arm32`, `_rv32` each `{$include}` their backend's
`asmtext_*.inc` and drive it directly, with no compiler around it. All four
failed at compile time on `undefined variable (InlineAsmLineHoleN)`, and
`test_x64enc` on `unresolved forward: AsmRecordGlobalFixup`. Nothing regressed:
the emitters grew an inline-asm line pool and a global-fixup sink *after* these
harnesses were written, and since nothing ran them, nothing said so. That is the
exact failure mode the sweep exists to end — an unrun test does not fail, it
just stops being true.

Each got an honest **mock**, not a copy of the real thing: the four line-pool
arrays as empty state the emitter can read (`MOCK_INLINE_ASM_LINES = 4`), and
`AsmRecordGlobalFixup` routed to `EmitGlobRef`, which its own GlobRef rows
already assert against. A mock that lies would be worse than the unwired file.

All six now run under `test-asm` with `-Fucompiler`, each row verified verbatim
before wiring.

### Two subjects with real oracles

- `test_ecdsa_sign` — self-asserting and wired as-is (`-Fulib/rtl`). It prints a
  1 per property and the reject rows are the half that matters: a verifier that
  answers true for everything passes sign+verify and fails `reject: msg/sig/key`.
- `test_residency_coswitch` — asserts the **property**, not the numbers. It
  builds at -O0/-O2/-O3 and requires the three outputs identical plus a 4-line
  count. Generators are a pxx extension, so FPC cannot be the oracle and nothing
  else states what `s=/x=/acc=/chk=` should be; recording today's values would
  defend whatever they are. The cross-`-O` identity IS the file's stated
  contract, and is what the float-spill bug it guards would break.

### The five "unwired" files that were wired all along

`c_def_hijack.c` and `olf_cmath.c` are C units a wired Pascal test `uses`;
`kwarg_overload_unit.pas` and `qualified_default_unit.pas` are units a wired
`.npy` imports; `test_exc_resident_param.pas` is **run at four -O levels** by
`test-opt`, which names it as a bare stem in a `for t in ...` loop and builds
`test/$$t.pas`, so no literal `test/…` token exists for the checker to match.
All five verified by reading the consumer, then exempted with the consumer named
— an exemption whose reason cites a specific wired caller stays checkable.

## Prio dropped 55 → 20 on 2026-08-21 (not a judgement on the work)

55 was right while ~60 files were unrun. With 15 left, every one of them in a
lane the user has explicitly deferred (N) or parked by definition (F), the
ranker was handing this back as the top Track A item on every `next` — a queue
that recommends work nobody may do. The number is the only lever that says so:
`ready`/`next` scan backlog, and there is no "deferred" state short of
inventing a blocker ticket that does not exist. Raise it back to 55 the moment
Track N or Track F reopens; the remaining work is 15 mechanical files, not a
design problem.

## Batch 4 — the 19 ESP programs, and the invocation that made them look broken (42 → 15)

All 19 `test_esp_*` wired into **`test-emit-obj`**, plus 8 more exemptions.
`test-emit-obj` and not `test-esp-bare`/`test-esp-idf` deliberately: those two
need Espressif qemu and a full IDF checkout, so on any ordinary box they SKIP —
and a check that skips is a check that does not run. These need neither, cost
~14s, and `test-emit-obj` is already in the `limited` and `full` tiers, so
Track T starts running them at the next sweep with no testmgr change (which is
T's file anyway).

Two assertions per program, answering different questions: the **x86-64 oracle
run** (every file compiles unchanged for the host — `PutC` becomes a `write(2)`
syscall — and its own comments state what it must print), and **it still builds
for both ESP ISAs**, which is the half the host run cannot cover because the
ESP branch of every `{$ifdef}` is dead code on x86-64.

Every expectation is transcribed from the author's own per-line comments
(`{ 14 }`, `{ Qxx }`, `{ 1 }`), or derived and checked: 3^20 = 3486784401,
`-9223372036854775807 div 1000003 = -9223344366821 rem -675344` (truncating
toward zero, both negative), `MakeVec(7,11,13,17,19,23,29,31,37)` →
`7000011 4199 120`. `test_esp_float_probe`'s 33 lines include two **0**s
(`d > e` and `d >= e` for d=3.0, e=4.0) — the tell that it is a transcription
and not "all ones".

Three that are not a plain run-and-diff, each for a stated reason:
- `test_esp_isr_register` prints nothing by design, so the assertion is the
  **structural** one its own header specifies: an absolute reloc against
  `MyIsr` for the IDF linker to fill, and `MyIsr` in `.iram1.text`.
- `test_esp_interrupt` has **no** x86-64 oracle — the host backend refuses
  `interrupt;` outright, which is the correct answer and not a gap — so it is
  an ESP-build check only.
- `test_esp_iram` additionally asserts `.iram1.text` EXISTS in both objects: a
  silently-ignored `iram;` leaves a program that runs correctly here and misses
  its deadline on the board.

### The finding worth keeping: a wrong invocation forges a compiler bug

The first pass built every file with `--target=xtensa --platform=esp
--emit-obj` and reported three "backend gaps": `unsupported node in IR codegen:
syscall` on xtensa for `test_esp_procaddr`/`_fastdoubles`/`_float_probe`, and
`undefined variable (PXXVarBinOp)` on riscv32. **All three were artifacts of my
own command line.** Those files test `PXX_ESP_BARE`, not `PXX_ESP`, so the IDF
profile compiled their HOST branch — the `__pxxrawsyscall` `PutC` — and the
xtensa backend correctly refused a Linux syscall node. Built as their headers
say (`--esp-profile=bare`), all three compile for both ISAs.

The two invocations are not interchangeable and each file picks one by the
symbol its own `{$ifdef}` tests: `PXX_ESP` → `esp_rom_printf`, an external the
IDF links, needs `--platform=esp --emit-obj`; `PXX_ESP_BARE` → a UART MMIO
store, needs `--esp-profile=bare`. Using the wrong one fails with a real-looking
error in the *backend*. That is a ticket I nearly filed against Track A, and
the reason I did not is the playbook's rule — read what the file asks for and
re-measure before writing a conclusion down. It is now a comment in the recipe
so the next reader spends zero minutes on it.

### Exemptions added (8)
`fpcv.pas` (an FPC oracle probe, not a test — it exists to be compiled BY FPC),
`t_rw.pas` (a GTK3 form app that blocks in an event loop; the LFM streaming it
shows is covered headlessly by the wired `test_lfm` pair),
`manual/test_pylexer.pas` (a hand-run token dumper with no pass/fail), and the
five `csqlite_*` files that need the gitignored amalgamation. For those five a
graceful-SKIP rule (the shape `test-sqlite-parity` already uses) is the better
end state than an exemption — but it cannot be written honestly from a checkout
with no amalgamation to run it against, and this sweep does not record
expectations it did not see produced.

Also documented in `UNWIRED.txt`: a reason may not START with `#`, or the
comment strip eats it and the line is refused as reason-less.

### Left for the next batch
Exactly the two deferred categories and nothing else: the 13
`test_pyeval_*`/`test_pyexec_*` (Track N, deferred by the user) and the 2
`test_softfloat_*` (Track F, parked by definition). Every other test file in
the repo is now either run by a rule or exempted with a reason naming what runs
it instead.


## 2026-08-30 (frankwasm) — the pause reason is gone, and the shape of the problem changed

**Not a resume. A re-measurement, because the summary had become false in both
halves.** It said 15 files remained and all 15 were in deferred lanes. Today:

| | then (2026-08-21) | now |
| --- | --- | --- |
| unwired total | 15 | **45** |
| the 13 Track N pyeval/pyexec | unwired, deferred | **wired** (108 Makefile references) |
| the 2 Track F softfloat | unwired, deferred | **wired** |
| `test/wasm/**` | — | **37** |
| top level | — | **8** |

Neither number in the old summary survived. The parked-on files got wired by
somebody who did not update this ticket; the ticket went on telling every reader
that the remaining work was blocked on a deferral that had already lifted.

### The 8 top-level files were ALL created today

    test/cabi_bridge.c                            3226a45ff
    test/cabi_intra.c                             53f148b61
    test/test_array_type_alias_chain.pas          78ec5b907
    test/test_frozen_str_array_elem_cap.pas       6e25bdcde
    test/test_generic_constraint_tobject_root.pas cce53aada
    test/test_length_of_a_dynamic_array_of_char.pas d79ee7c95
    test/test_loadfile_into_element_and_field.pas 4f73f88fa
    test/test_ptr_depth2_bases.pas                df0661eff

All eight added 2026-08-30, by `--diff-filter=A`. One of them (`78ec5b907`) is
mine. Nine more of mine — the whole `feature-unicodestring-model` test family,
including that campaign's ACCEPTANCE test — were unwired until `d24df3f09`
tonight and are not in the count above only because I wired them first.

**So this is a leak, not a backlog**, and the ticket's own batch-1 note said so
in 2026-08-19: *"the orphan population grows faster than it drains, so
twenty-one was a snapshot and never a census."* That sentence has now been true
for eleven days and the ticket is still framed as a drain.

### The gate exists, is red, and is invisible where it matters

`tools/test_wiring_gate_devtest.py` runs the checker and exits 1 today.
`tools-devtest` collects it — into **limited and full only**, deliberately not
`native`, because native is the tier dev boxes gate their pushes on and harness
guards must not inflate that number. That reasoning is sound and I would not
change it. The consequence is that a lane agent adding an unwired test gets no
signal at all until the next full sweep, which is where `tools-devtest#00` has
been STILL-RED since at least `49bd043` (2026-08-29).

**The interesting question this raises is not for this ticket.** Draining 45
files does nothing about the eight-per-day inflow. What would is a cheap
per-push signal — the checker is instant, so a lane agent's own `gate.sh quick`
could name a test it just added and never wired, without putting the whole guard
family into `native`. That is Track T's tool and Track T's call; noted here
rather than filed, because the sweep is worth doing either way and this is one
sentence, not a design.

### Method unchanged, and the hard rule matters more than usual here

Every expectation must be an ORACLE (FPC 3.2.2 for Pascal, gcc for C), never a
recording of today's output. Two files in an earlier batch shipped AS THE
REGRESSION TEST FOR THEIR OWN FIX, so transcribing what the compiler prints
would have pinned whatever the fix happened to leave behind — including a bug.
That risk is higher for these eight than for any earlier batch, because they are
hours old and came from fix commits landed today.

## Batch 5 — 2026-08-30 (frankwasm). 45 -> 37, and the remainder is one campaign's

Six subjects wired, two exempted, one stale exemption removed.

| file | disposition | oracle |
| --- | --- | --- |
| `test_array_type_alias_chain.pas` | wired | FPC 3.2.2, diffed |
| `test_frozen_str_array_elem_cap.pas` | wired | FPC 3.2.2, diffed |
| `test_generic_constraint_tobject_root.pas` | wired | FPC 3.2.2, diffed |
| `test_length_of_a_dynamic_array_of_char.pas` | wired | FPC 3.2.2, diffed |
| `test_ptr_depth2_bases.pas` | wired | FPC 3.2.2, diffed |
| `test_loadfile_into_element_and_field.pas` | wired | `wc -c` of its own `.data` = 14 |
| `cabi_bridge.c` | **UNWIRED.txt** | — |
| `cabi_intra.c` | **UNWIRED.txt** | — |
| `lib_mimic_xml_dom_minidom.npy` | exemption **removed** | it is wired now |

**"Diffed", not "checked".** Each recorded string was proven equal to its oracle
by `diff <(fpc-built) <(pxx-built)`, not by reading two outputs side by side.
That distinction is the whole content of the hard rule: a transcription that
*looks* right is what pins a bug.

The `LoadFile` one has no FPC oracle — FPC has no `LoadFile` — and `wc -c` of
the data file is a **better** one than FPC would have been, because it is
independent of every compiler. Worth noting for the next drainer: "no FPC" is
not the same as "no oracle", and reaching for the recording is a step you take
only after asking what the program is actually asserting. Here it asserts a byte
count that is sitting in the filesystem.

### The two C files must NOT be wired, and that is the finding

`cabi_bridge.c` and `cabi_intra.c` are the implementations of
`unit_cabi_bridge.pas` / `unit_cabi_intra.pas`, reached by `uses
'./cabi_bridge.c'` from wired subjects. **Compiling either standalone would test
a shape that never occurs** — `cabi_intra.c`'s entire subject is a C-to-C call
inside a translation unit that a Pascal program uses (`CProgramMode` and
`CUnitOfPascalProgram` both True), a state no standalone compile can enter.

Same path-form blind spot `test/relpath/*` is already exempted for: the checker
matches by STEM and cannot see `uses './x.c'`. **An exemption with a reason is
the correct end state here, not a concession** — and it is also the honest form
of a skip for the *other* case, a file whose expectation cannot be constructed.
Leaving such a file unwired with a stated reason keeps it findable; wiring it
against its own output makes it permanently green and permanently silent, and it
then gets cited as coverage.

### Re-priced 20 -> 40, and the reason is the mechanism rather than the incident

**p20 was not a wrong judgment. It was a correct judgment about a different
object.** The ticket described a drain of 15 files blocked on deferred lanes,
and at that description p20 is generous. The object is a leak: all eight
top-level files in this batch were created the same day, verified individually
with `--diff-filter=A`, and nine more (the whole `feature-unicodestring-model`
family, including that campaign's ACCEPTANCE test) were unwired until the same
evening and are absent from the count only because they were wired first.

`prio:` is downstream of the `summary`, so the two go stale together and the
ranker keeps faithfully rendering a correct judgment about an object that no
longer exists. The countermeasure used here: **the number lands in the same
commit as the evidence**, never as a bare frontmatter edit.

40 rather than higher because the *drain* is mechanical and the valuable half is
not in this ticket at all — see below.

### What is left is 37 files and they are all `test/wasm/**`

Not a general backlog any more. That is one campaign's staging set
(`feature-target-wasm`), and whether those files should be rules, a script, or
exemptions is a question for whoever holds that campaign — not for a sweep. The
top-level population is **zero** for the first time this ticket has existed.

### The inflow is the real problem and it is not this ticket's to fix

Draining 45 does nothing about eight a day. `tools/test_wiring_gate_devtest.py`
exits 1 today and `tools-devtest` collects it into limited+full, deliberately
**not** `native`, because native is what dev boxes gate pushes on and harness
guards must not inflate that number. That reasoning is right. The consequence is
that an agent who adds an unwired test gets no signal for days.

Suggested to frankT directly (a sentence in a ticket is not a message, which is
exactly how a checker exiting 1 stayed unread all day): have `gate.sh quick` ask
the cheap per-push question — *did THIS push add a file under `test/` that no
rule references?* — rather than the expensive census. One push's diff, instant
checker, native's number stays honest, and the signal lands on the person who
still has the oracle in their head.
### The remaining 37, measured — and the answer is NOT "wire them"

Checked rather than assumed, because "37 unwired files" invites a batch 6 that
would be wrong.

`test/wasm/` holds 37 `*_slice.pas` subjects **and 38 `check_*.sh` scripts**,
one per slice, plus `check_all.sh` and `wat_oracle.sh`. The chain is real and
complete: `check_all.sh` -> `check_<name>.sh` -> `<name>_slice.pas` (verified,
e.g. `check_set.sh` names `set_slice.pas` three times).

**The break is one level above every file the checker names: `test/wasm` appears
NOWHERE in the Makefile.** Not the slices, not the check scripts, not
`check_all.sh`. An entire test lane — 37 subjects, 38 harness scripts, its own
oracle script — runs only when a human types it.

The checker reports the 37 leaves because it scans build rules and `tools/`, and
these are driven from `test/wasm/*.sh`. So the leaves are a **symptom with the
wrong coordinates**: wiring 37 slices individually would duplicate a harness
that already exists and is better than a rule per file.

**And `check_all.sh` exists because this lane already lost a suite to exactly
this class of problem.** Its own header:

> *"This exists because a suite went red and stayed red across a handoff that
> reported it green... green looked like the ABSENCE of output. That is
> indistinguishable from a script that died at line 1, which is exactly what had
> happened."*

The fix was a positive sentinel per check — `PASS <name>`, unreachable under
`set -e`. Correct, and one level short: a sentinel proves the check ran *when
someone runs the check*. Nothing runs `check_all.sh`.

**Not batch 6, and not this ticket's call.** Whether that lane becomes a make
target, stays a hand-run harness with an UNWIRED exemption per slice, or is
gated on a wasm runtime this box may not have, is a decision for whoever holds
`feature-target-wasm`. Two of those three answers involve no new rules at all.
Reported to the coordinator rather than acted on.

What this ticket can say with confidence: **the general unwired-test backlog is
empty.** What remains is one campaign's harness with a missing top-level hook,
which is a different problem with a different owner and a one-line fix if the
answer is "a make target".


## RESOLVED 2026-08-30 — the backlog this ticket was written to drain is empty

Not "finished the list" — **the list is a different list now.** What remains
under `check_test_wiring.py` is 37 `test/wasm/**` files that are not orphan
tests at all: they are a complete harness (37 slices, 38 `check_*.sh`,
`check_all.sh`, `wat_oracle.sh`) missing its top-level hook. Wiring them
individually would duplicate a runner that is better than a rule per file.
Recorded in `feature-target-wasm` with three candidate answers; **do not open a
batch 6 for them.**

**The inflow, which this ticket could never have fixed, now has an owner.**
Draining 45 does nothing about eight a day. frankT built the per-push question
into `gate.sh quick` (`7c1c422c9`) — *did THIS push add a file under `test/`
that no rule references?* — scoped inside the checker as `--since`, cannot-scope
reported as exit 2 rather than a pass, and a failure message that names
`test/UNWIRED.txt` and says outright not to delete the test to clear it. Cost
measured at 0.7-1.3s against quick's ~30s budget.

That is the half that matters. This ticket drained a population; that check
stops it refilling, and it lands on the person who still has the oracle in their
head rather than on a sweep three weeks later reconstructing it.

### What the drain was actually for, stated once

An unwired test is not a missing test — it is **a test that cannot fail**. Nine
of them were `feature-unicodestring-model`'s entire family, including that
campaign's acceptance test: written, measured against FPC, quoted in three
messages to other agents, and executed by nothing but one person's hand. The
campaign was one message from closing on it.

The rule that follows, and it is the one to keep: **whether a test executes is
not a property visible from inside it.** Reading the sources finds every
property the sources carry and none of the ones they don't.
## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
