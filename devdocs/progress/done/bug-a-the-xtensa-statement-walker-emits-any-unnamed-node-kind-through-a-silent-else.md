---
slug: bug-a-the-xtensa-statement-walker-emits-any-unnamed-node-kind-through-a-silent-else
track: A+S
prio: 45
type: bug
status: done
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "FIXED. Five backend walkers ended in `else IREmitNodeX(i)` -- a DENYLIST of value kinds with `emit` as the default -- while x86-64 is an ALLOWLIST with no catch-all and so never had this bug. That inverted default is the root cause: 77 IR kinds exist, 37 are statements, and the five denylists named at most 24 of the other 40 and DISAGREED with each other on 8. Not five kinds and not xtensa alone, as this ticket first said: 24 value kinds reached xtensa's else and riscv32 was missing IR_CLONE and IR_DYNUNIQUE too. Replaced by one IRKindIsStatement in ir.inc, deleting all five lists. Behaviour-preserving by measurement, not argument."
---

# The xtensa statement walker emits any unnamed node kind through a silent `else`

`IREmitMachineCodeXtensa` walks every IR node in the body and switches on kind.
The `case` ends:

```
IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK, IR_CONST_DATA,
IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
IR_SLOTADDR, IR_FIELD, IR_INDEX: ;
{ IR_ATOMIC is a value node consumed by its parent store, like
  IR_SYSCALL. Emitting it at statement level TOO runs the
  read-modify-write twice — riscv32 and arm32 both paid for this one. }
IR_ATOMIC: ;

else
  IREmitNodeXtensa(i);
```

**The default for an unknown kind is to EMIT it.** For a statement node that is
right. For a VALUE node it is wrong twice over: the value is computed at
statement level where nothing wants it, and the parent that does want it
computes it again — so anything the subtree does, it does twice.

## This is not hypothetical; it has fired twice

- **IR_ATOMIC** — the comment above is the scar. A read-modify-write ran twice.
- **IR_VIRTUAL_CALL** — `57e35555e`, 2026-09-02. Every virtual call whose result
  was used ran its callee **twice** on xtensa, side effects and all. It reached
  the backlog as a string allocation count (7707 vs 3799) and was neither about
  strings nor about allocation.

Both were fixed one at a time, in the arm. Neither fix touched the mechanism
that will produce the third.

## What is still unnamed

Named in riscv32's and/or arm32's walkers, absent from xtensa's, therefore
reaching the `else`:

`IR_LOAD_MEM` · `IR_SET_LIT` · `IR_SET_BINOP` · `IR_SET_CMP` · `IR_DYNUNIQUE`
(plus `IR_CLONE`, `IR_ZERO_SYM`, `IR_IO_LOCK`, `IR_IO_UNLOCK` in arm32 — the last
three are statement nodes, where the `else` happens to do the right thing).

riscv32 groups `IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_CONST_DATA,
IR_SLOTADDR, IR_DYNUNIQUE, IR_FIELD, IR_INDEX` into its **do-nothing** arm, which
is the shared IR saying these are value nodes.

**MEASURED, and read narrowly:** a side-effect counter driven through a set
literal containing a call, `in`, a set binop and a dynamic-array unique does NOT
double on xtensa (50 per 50 iterations, matching x86-64). That is a result about
those four shapes. It is **not** a clearance of the catch-all, and it is not a
reason to close this — the same probe run against `k := o.F(i)` before
`57e35555e` would have come back doubled, and nobody ran it for two days.

## The fix shape

Two candidates, and this ticket does not pick:

1. **Name every kind and delete the `else`** — or make the `else` an `Error`.
   Then a new IR kind fails loudly at the one place that must decide whether it
   is a statement or a value, instead of defaulting to the answer that is wrong
   for half of them. This is the `normalise-dont-special-case` answer and it
   deletes a case rather than adding one. Cost: every kind must be classified
   once, and a kind that legitimately relies on the `else` today has to be
   listed.
2. **Guard by IRStmtRoot generally** rather than per-kind — emit at statement
   level only what was marked a statement. Cheaper, but `IRMarkStatementNode`
   only marks IR_CALL / IR_VIRTUAL_CALL / IR_CALL_IND today, so everything else
   would need marking first, and that is the same enumeration by another road.

Whoever takes it should check the other backends for the same shape before
changing xtensa alone — arm32 and riscv32 have longer lists, which is not the
same as having no `else`.

## Gate

`make compiler/pascal26` plus the xtensa rows; `test_virtual_call_runs_once.pas`
is the existing regression for the IR_VIRTUAL_CALL instance and must stay green.
A fix here should come with a probe for at least one of the five unnamed kinds
that can be shown to go red if that kind were mis-emitted — a change to this
`else` that nothing can fail is not a change anyone can trust.


## FIXED 2026-09-02 (frankC) — the DEFAULT was inverted, which is why it kept recurring

This ticket named a symptom (xtensa's `else`) and guessed at scope. Both were
too small, and the correction is the finding.

**Root cause.** x86-64's walker is an **ALLOWLIST**: it names the 37 statement
kinds and has **no `else` at all**, so an unnamed kind does nothing. The other
five are **DENYLISTS**: they name the value kinds to skip and `else` emit. So
the default for a kind nobody classified was **skip on x86-64 and EMIT on every
other target**. aarch64's own walker already said so in a comment — *"x86-64's
driver has no statement-level catch-all, so it never had this bug"* — and that
sentence sat one screen above the defect for however long.

**Measured, 2026-09-02.** 77 IR kinds declared; 37 are statements on x86-64, 40
are not. The five denylists name at most 24 of those 40 and **disagree on 8**:

| kind | missing from |
| --- | --- |
| `IR_CLONE`, `IR_DYNUNIQUE` | riscv32, xtensa |
| `IR_LOAD_MEM`, `IR_SET_LIT`, `IR_SET_BINOP`, `IR_SET_CMP` | xtensa |
| `IR_VAR_BOX`, `IR_VAR_BINOP` | i386, arm32, riscv32, xtensa |

**This ticket's own numbers were wrong** and are corrected above: not "five
kinds", and not xtensa alone — **24** value kinds reached xtensa's `else`, and
**riscv32 was missing two as well**. Ranking followed the wrong number.

**The fix deletes cases.** One `IRKindIsStatement` in `ir.inc` — the x86-64
allowlist hoisted, because whether `a + b` is a statement is a property of the
IR and not of a machine — and all five denylists go away. Verified as a drop-in
before it was written: every backend's explicitly handled statement arms are a
**subset** of x86-64's 37, so the guard can only narrow what reaches the
emitter, never broaden it.

### The risk this ticket did not name, and how it was cleared

Whether any of the 40 non-statement kinds was being emitted through some
backend's `else` **and needed there** — `IR_RESOURCES`, `IR_RTTI_REG`,
`IR_FRAME`, `IR_FPU_MASK` were the candidates. A read cannot answer that.
Cleared by an isolating pre/post differential (below), plus reading the emitter:
`IR_RTTI_REG` and `IR_RESOURCES` load an address into the result register and
have no side effect, so they are values, and x86-64 has always declined to emit
them at statement level.

### The guard, and the break that proves it can fail

`test/test_ir_value_node_not_emitted_as_statement.pas`, wired into the native
suite and `test-i386` / `test-aarch64` / `test-arm32`.

**It cannot fail on today's tree — so the break was measured, not assumed.**
Adding `IR_ATOMIC` to `IRKindIsStatement` (mis-classifying one value kind as a
statement, which is precisely the historical bug) makes it **exit 81 — n = 12 —
on i386, aarch64 and arm32**, and leaves **x86-64 at 0**, because x86-64's
walker has no catch-all to poison. That asymmetry is itself the ticket's thesis,
reproduced on demand.

The assertion is on the **count**, not the returned value: a doubled
read-modify-write still returns a plausible number, so a row checking only `r`
would pass while `n` was wrong.

**riscv32 is NOT wired**, and that is a gap rather than a pass: it has a
catch-all and therefore can regress, but it rejects `InterLockedIncrement`
outright, so this probe cannot be built for it. A riscv32 row needs a different
value kind with an observable side effect.

### The differential, and the false attribution it produced first

The first pre/post run credited this change with **fixing** `test_string_n_array_field_stride`
on i386, aarch64 and arm32 — a real record-field stride bug that writes 224
bytes past the end of a record. That was **wrong, and the error was in the
baseline, not the reasoning.**

The "pre" compiler had been snapshotted **before the `git pull` that opened this
ticket**, so the differential was comparing *(old tree, no change)* against
*(new tree, change)* and attributing everything in between to the change.
CLAUDE.md says exactly this — *rebuild after any sync touching `compiler/**`
before you measure* — and it was broken by copying a binary that was already on
disk rather than building one.

**What makes it worth recording is that the wrong answer was the FLATTERING
one.** A differential that credits your change with fixing a memory-corruption
bug on three targets does not invite a second look; it invites a commit message.
The tell was a contradiction the instrument could not explain: an instrumented
build showed that on i386 **every** kind this test reaches was already in the
old denylist, so the catch-all could not have been emitting anything for it, and
the measured "fix" had no mechanism. Reasoning said no change, measurement said
big change, and the measurement was the one that was wrong.

Attribution was settled by `git stash`ing only the six compiler files and
rebuilding: **the unchanged tree passes that test too**. Both binaries then
reproduced their shas exactly, so the pair is sound.

Note the two binaries of the *same* sources differed (`ba1eba0d8d39` vs
`b1b8ca4d5435`) — two valid self-host fixedpoints reached from different seeds,
which CLAUDE.md already describes and which is **not** a miscompile. It is,
however, enough to change generated code, so a snapshot binary is not
interchangeable with a rebuild of the same tree.

**Corrected result: this change is behaviour-neutral**, measured over the corpus
on i386/aarch64/arm32/riscv32 with a harness carrying both controls (see below).

### The harness needed three fixes before it could be believed

None of them were about the compiler.

1. **It compiled the two binaries to different paths**, and a program's own path
   leaks into loader errors and `argv` — so `test_c_argspill`, `test_c_crypt`
   and `test_c_lazycasing` were reported as differing when both sides failed
   identically on a missing `.so`. Fixed by reusing one output path.
2. **It read `$?` after a pipeline**, which is the *last stage's* status, so
   every `Halt()` code was discarded. This made the harness **unable to fail**:
   pointed at a compiler proven to miscompile the probe, it reported agreement
   on all three targets. Caught only because a positive control was run.
3. **Three reported rows were harness artefacts, not codegen.**
   `lib_mimic_urllib_request_server` (a server) and `lib_strtofloat_lemire` (a
   time-bounded random fuzz whose output depends on how far it gets before the
   timeout) are nondeterministic — both confirmed unstable running the **same
   binary twice**. `lib_rsa` is perfectly deterministic and was an artefact of
   the harness's own **10-second timeout**: it is slow under qemu, so the two
   runs were truncated at different points. Given 40 seconds both sides are
   byte-identical and pass.

**All three failure modes report a difference that is real about the harness and
false about the compiler** — which is the same sentence as the false attribution
above, and the reason every row here was chased to a cause instead of counted.

### The corrected differential — the number

`b1b8ca4d5435` (HEAD without this change) against `45d97297aeaa` (HEAD with it),
both freshly built and both reproducing their shas: **6644 pairs** — every
`test/*.pas` against i386, aarch64, arm32 and riscv32 — compared on **stdout,
stderr and exit code**.

**16 raw rows. 0 real behavioural differences.** Every row was chased to a
cause rather than counted:

| rows | cause |
| --- | --- |
| 2 | genuinely nondeterministic (`lib_mimic_urllib_request_server`, `lib_strtofloat_lemire`) — confirmed unstable running the **same binary twice** |
| 14 | the harness's own 10s timeout under 8-way qemu contention — **identical at 90-150s** |

Both controls held on the final pair: pointed at a compiler with `IR_ATOMIC`
deliberately mis-classified it reports on i386/aarch64/arm32, and pointed at the
real one it is silent.

**This is a behaviour-preserving change, measured** — which is what the subset
argument predicted and is now not merely argued.

### What this does NOT claim

It does not claim the 8-way drift was latent everywhere. It claims **no shape in
this corpus, on these four targets, reached a kind where the five denylists
disagreed in a way that changed output.** 6644 pairs is a rate, not a proof of
absence, and xtensa is not in that number at all — it has no qemu row here and
is the backend with the **most** unnamed kinds (24). Its coverage is the
existing xtensa Makefile rows plus the fact that the change can only ever
narrow what reaches the emitter.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7a995fe4e.
