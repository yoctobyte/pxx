
---

## 2026-08-29 — CORRECTION: every "48/48 corpus hashes identical" in this ticket was a vacuous diff

Found while checking a routine claim, not by anything failing. **The scratchpad
corpus harness did not export `PXX_HOME`.** A compiler binary copied into the
scratchpad cannot find its RTL from there, so every row came back `FAIL` — and
`FAIL` compares equal to `FAIL`. Both sides compiled **nothing**, the diff was
empty, and the harness printed what reads as total agreement.

> **A diff of two totally-failed runs is a passing diff.** The comparison has no
> floor: it reports agreement most confidently when it has measured least.

Same shape as the `make compiler/pascal26` no-op in a seeded tree already written
up in CLAUDE.md — a success message in the wrong dialect, with nothing downstream
to notice. Both are the eighteen-face signature: the failure is indistinguishable
from the success by its output alone.

The harness is fixed (exports `PXX_HOME`, skips the 3 corpus files that are
`unit`s and can never compile standalone, and **exits 2 with a loud line if no
row produced a hash**). The real row count is **25**, not 48: 8 corpus programs x
6 targets = 48, minus 8 xtensa rows (that target has no dynamic-symbol support
and the corpus pulls in `calloc`) minus 3 units x 5 targets.

**Every claim was re-run against the actual binaries, and every one holds:**

| step | claimed | actually |
| --- | --- | --- |
| W1 -> W2 (x86-64 W2) | 48/48 identical | **identical, 25 rows** |
| W2 -> item 3 (x86-64) | 48/48 identical | **identical, 25 rows** |
| aarch64 item-1 port -> item 3 | 48/48 identical | **identical, 25 rows** |
| item 3 -> W2 (aarch64) | 48/48 identical | **identical, 25 rows** |

So the conclusions stand and nothing landed on bad evidence — but they *stood on
nothing* until this re-run, and the commit messages for `0b4805f8e` and its
siblings overstate the check as "48/48". Those messages are history and stay as
written; **this table is the correction.** The number to quote from here on is
25 rows, and the harness now refuses to answer at all rather than answer
emptily.

## 2026-08-29 — item 3's exception gate: CHARACTERISED, PRICED, and NOT LIFTED

### The reader, and how to tell it from the alternatives

The gate is `if RcProcHasExc then Exit` in `ResidentSlotIsDead`. It came from a
poison run that found *a* reader and never characterised it, so nobody could say
whether proc-wide was necessary or merely sufficient. Three hypotheses were live:
the landing-pad refresh, the unwinder reading frame slots, or setjmp/longjmp
restore semantics.

`PXXDBG=a.noexcrefresh` (new, both targets, `9d46bff96`) suppresses the
`IR_EXC_ENTER` landing-pad refresh, which makes the three produce **three
different values** in the handler instead of one correct one:

| handler sees | mechanism | consequence |
| --- | --- | --- |
| the **latest** value | registers survived the raise | refresh is dead code, gate deletable outright |
| the **try-entry** value | `ExcLongJmp` rolled the register back out of the jmp_buf | refresh is load-bearing |
| **$5EEDADAD** (with `a.poisonslot`) | a reader other than this loop | the gate is not about the landing pad at all |

Measured, x86-64 `-O3`: `IN seen` 9453 -> **9316**, which is exactly sum 1..136,
the try-entry value at the raising iteration. `MIX a` 633 -> 630, `NEST y` 1077 ->
76, `FIN n` 90 -> 89. Try-entry values, every one.

**So: the reader is the landing-pad refresh, its cause is the longjmp rollback,
and there is no second reader.** Consistent with the stubs — `ExcSetJmp` saves
r12-r15 (aarch64 x19-x28), `ExcLongJmp` restores them, and the raise path touches
only `BSS_EXC_*` and the jmp_buf. The discriminator is recorded because a
correctness suite cannot distinguish *"the slot is never read"* from *"the slot is
read and happens to hold the right value"*, which is the whole reason item 3
needed poison rather than tests.

### The partition falls out of the same run, and it is per-symbol

Only residents **written inside** a protected region moved. `OUT`, `THR` and
`PAR` — written outside — did not. `MIX` has both classes in **one body**: `ins`
moved, `outv` did not. So the exposure is per-symbol, not per-proc, **on
measurement rather than on argument**, and the proc-wide gate is strictly coarser
than the truth.

`SymWrittenInProtectedSpan` (`e967f9038`, report-only) computes it, and agrees
with the measured partition **15/15**.

### The prize — and it is why this stops here

| population | int residents | recoverable (`exc=1 excwr=0`) | must keep dual-write |
| --- | --- | --- | --- |
| `compiler.pas` (self-host) | 3049 | **0** | 0 |
| chess | 388 | 3 | 0 |
| mandelbrot | 378 | 0 | 4 |
| jsondemo | 1124 | 3 | 0 |
| NilPy: xml.etree | 1061 | 3 | 0 |
| NilPy: collections.abc | 1056 | 6 | 0 |
| NilPy: codecs | 1256 | 3 | 0 |

**Zero in the compiler** — it contains 9 `try` statements in total and not one of
them is in a proc that also gets a resident, so the self-host benchmark cannot
move by a single instruction. Under 1% everywhere else, and the qualifying sites
are `Repl`, `RunTUI`, `pyiter_has` — **driver loops, not hot ones**. The NilPy
guess (Python leans on exceptions, so its population should be larger) was
checked and is wrong: 0.3-0.6%, same as Pascal.

**Verdict: do not lift the gate.** The change is correct, designed, and cheap to
write — and it would trade a wrong value on the *unwind path*, the
highest-consequence and least-exercised path in the compiler, for under 1% of
residents in driver loops and exactly nothing in the self-host. The coarse gate
costs almost nothing because exception-bearing procs in this codebase are not the
hot ones. That is a property of the code, measured across four independent
populations, and it is the answer.

What survives and is worth having: the discriminator, the test, the analysis, and
a stated re-open condition — **if a workload appears whose hot loop sits inside a
try, re-run `PXXDBG=a.resid` and read `excwr=`; the design below is ready.**
Expose iff written-inside; the landing pad must then skip the refresh for exactly
the symbols whose slot is dead, which is the *same* predicate on both sides
rather than two rules that must be kept in agreement.

**Per-symbol is the correct granularity, not per-site.** A symbol with any
in-span store must dual-write at *every* store, because the last store before a
raise may have been an out-of-span one and the landing pad refreshes from the
slot regardless. Recording this because per-site looks like a free improvement
and is silently wrong.
