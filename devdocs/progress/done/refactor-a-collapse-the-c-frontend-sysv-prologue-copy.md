---
track: A
prio: 60
type: refactor
status: done
found: 2026-08-30
found-by: claude-A
owner: frankC
---

# There are now TWO SysV prologue emitters; collapse `cparser.inc`'s into the shared arm

`EmitParamSpillsForTarget` (`compiler/ir_codegen.inc`) exists precisely to be the
one place a frontend gets its incoming parameters homed. Its own header comment
records why: NilPy's `PyEmitParamSpills` and Rust's `REmitParamRegSpill` were
private raw-x86-64 copies, and a NilPy or Rust program built for a cross target
spliced x86-64 bytes into an ARM instruction stream and SIGILLed. Both copies
were absorbed. `pyparser.inc:19066` still carries the tombstone.

**The C frontend's copy was never absorbed.** `cparser.inc:11282` has a full SysV
classification — independent int/SSE counters, stack overflow from `[rbp+16]`,
`tySingle` narrowing — because C needed a SysV prologue before the shared layer
existed and the shared layer only spoke the internal convention.

`feature-cdecl-bodied-sysv-prologue` has now added a SysV arm to
`EmitParamSpillsForTarget`, mirrored from that C code deliberately rather than
reinvented. So the count went from one copy to two. That is the wrong direction,
and `devdocs/dev/normalise-dont-special-case.md` is explicit about which way it
should go: the second path is the one that stays broken.

**Why it was not done in the same change:** `cparser.inc` was held by another
agent (the csmith campaign) at the time. Sequencing, not disagreement.

## The work

Have the C function-body emitter call `EmitParamSpillsForTarget` and delete the
inline classification at `cparser.inc:11282`. Then a bug fixed in one is fixed in
both, which is not true today.

Two things to preserve, both load-bearing:

- The variadic register-save prologue and the `__va_overflow` anchor are C-only
  and interact with this homing (`ProcNamedGP` / `ProcNamedFP` seed `va_start`'s
  `gp_offset`/`fp_offset`). They must not be flattened into the shared arm.
- The C arm reads declared types from a local `ptypes[]`; the shared arm reads
  `Syms[idx].TypeKind`. Confirm they agree for every C parameter shape before
  swapping — a C declaration can carry a type the symbol does not.

## Gate

`make compiler/pascal26` + byte-identity of the C corpus against the pre-change
binary, built at one HEAD. The collapse should change **no** emitted byte; if it
does, the two copies had already drifted, and that divergence is the real finding
and deserves its own ticket.


---

# UPGRADED 2026-08-30: this is the ROOT CAUSE of a five-red incident, not tidiness

Filed as a duplication smell. It is more than that. `cparser.inc` does not have
*one* prologue spill with a copy — it has **three per-target spills that disagree
with each other about which convention a C function uses**:

| target | cparser's prologue spill | so a C function is... |
| --- | --- | --- |
| x86-64 | `cparser.inc:11282` — genuine SysV, independent int/SSE counters | **C-ABI** |
| aarch64 | `cparser.inc:11178` — positional, *"mirrors the Pascal aarch64 spill"* | **internal** |
| arm32 | `cparser.inc:11128` — positional, word-based | **internal** |

**A C function's calling convention therefore depends on the target**, and
nothing names that fact in one place. Every call site that wants to know "is this
proc reached by the C ABI?" has to encode the answer per target, and it is not
the same answer.

## What that cost

`bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32` — five
p70 NEW-REDs (four `test-c-conformance-aarch64` shards and `test-lua-cross`).
`ProcExternal[p] or ProcCdecl[p]` is **correct on x86-64 and wrong on
aarch64/arm32**, purely because of the table above, and the same expression had
already been paid for once at `b362` on the indirect arm.

The `and (not CProgramMode)` guards now present on the aarch64 and arm32 call
arms are **compensating for this table**. They are correct, and they are a
workaround: they exist to stop a C-mode callee being called by a convention its
own prologue does not implement. Collapse the spills onto
`EmitParamSpillsForTarget` and C functions use one convention per target *by
construction*, the guards describe something real instead of patching something
accidental, and `ProcCdecl` means the same thing everywhere.

Three strikes on this predicate so far: `b362` (indirect, lua + sqlite),
`eeb51710e` (aarch64 direct), `6d2939f38` (arm32 direct).

## Sequencing note

`EmitParamSpillsForTarget` now has C-ABI arms for x86-64, aarch64, arm32 and i386
(from `bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`),
so the shared destination for the collapse **already exists on four of five
targets** and grows as that campaign finishes. Doing this after that campaign is
cheaper than doing it now, and doing it at all is what stops strike four.

Still blocked on `cparser.inc` being held by the csmith campaign.

## The implementer count is FIVE, not two — counted 2026-08-30 during frankA's riscv32 fix

Relayed by the coordinator, and it is the strongest argument this ticket has,
because it was produced by someone discovering it the hard way rather than by
reading the code looking for duplication. frankA began its riscv32 stack-argument
fix believing there was **one** implementer of the descending overflow layout,
told the coordinator **three**, and shipped **five**:

| file | role | sites |
| --- | --- | --- |
| `ir_codegen_riscv32.inc` | the caller side — `IR_CALL`, `IR_CALL_IND`, `IR_VIRTUAL_CALL` | 3 |
| `ir_codegen.inc` | Pascal callee spill | 4 |
| `cparser.inc` | **C-mode callee spill** | 3 |

`IR_CALL_IND` is the shape **a C function pointer takes**, and it was the last
place that should have kept a private layout. The change nearly shipped with two
of three caller shapes still descending — which would have been a convention
split between Pascal and C-mode, strictly worse than a uniform-but-wrong layout.

**That is this ticket's thesis, demonstrated three times in one afternoon by one
person.** Five places a convention is written down is five places the next change
to it gets forgotten, and the forgetting was caught by measurement rather than by
review both times.

## Carry into the collapse: expect one arm to be RIGHT already

frankA's fix was a **deleted case, not an added one**. The reordering code already
existed as the *variadic* tail reversal, gated on `ProcVariadic`, because a
`va_arg` walk reads forward from overflow and therefore needed psABI order. That
path was correct; the ordinary path was wrong. The fix removed the gate rather
than adding a second case.

The lesson for four admission shapes: **the conformant layout was already in the
tree, reachable only through the one path whose consumer would have noticed.**
When reconciling the shapes here, expect at least one to be correct already — the
win is deleting the other three, not synthesising a fifth.

## DONE for x86-64 — byte-identical, 2026-08-30 (frankC)

`cparser.inc`'s x86-64 SysV arm is gone: **-146 lines, +26**, replaced by
`EmitParamSpillsForTarget(procIdx, nparams)`. Two copies are one copy.

### The prerequisite was measured, not assumed

The ticket said to *"confirm they agree for every C parameter shape before
swapping — a C declaration can carry a type the symbol does not"*, because this
copy read `ptypes[]` and the shared arm reads `Syms[idx].TypeKind`. I put a
temporary probe in the spill path printing every disagreement and compiled:

- array decay — `int a[]`, `int a[10]`, `int a[][4]`, `char *p[]`
- function-pointer params, `struct S` by value AND by pointer
- `float`/`double` mixed with integers, `long long`/`unsigned long long`,
  `char`/`short`/`int` widening, `const char *`, `void *`
- the 829-proc csmith program

**Zero mismatches.** The probe was reverted before the collapse; the finding is
what licensed it.

### Dispatch is correct by construction, not by the call site knowing

`EmitParamSpillsForTarget` takes its SysV arm only for `ProcCdecl[procIdx]`.
In C that is `True` exactly for a genuinely new C-defined proc
(`cparser.inc:10736`, gated on `wasNewProc`) and `False` for a C declaration
bound to a Pascal routine (`:10762`, the `mangBound` path) — and that one MUST
keep the Pascal prologue, which is what it now gets. The call site passes no
convention flag and cannot get it wrong.

### Gate: no emitted byte changed

The ticket's own gate. Same source, one HEAD, pre- and post-collapse binaries:

| program | emitted output |
| --- | --- |
| `test/csmith/hang_builtins_700082.c` (829 procs) | **identical** |
| `test/c_pasunit.c` | **identical** |
| 12-shape parameter probe (decay, fn-ptr, struct, float) | **identical** |
| `test/cbitfield_mixed_type_pack_b373.c` | **identical** |

Behaviour unchanged too (`rc=0`, `rc=42`, `rc=0`), self-host fixedpoint
`22acd0c28479` converged in 1 round, `tools/gate.sh quick` GREEN.

Nothing had drifted between the two copies — which is the good outcome, and was
not knowable without checking.

## What is deliberately NOT in this change

**The aarch64 / arm32 / i386 / riscv32 arms stay.** They are not a second
instance of the same refactor and must not be bundled into it:

- The x86-64 collapse is **byte-identical** — the two implementations already
  agreed, so it is a pure deletion.
- Those arms are **positional/internal** (`cparser.inc:11143` arm32,
  `:11193` aarch64 — the latter says outright it *"mirrors the Pascal aarch64
  spill"*). Collapsing them onto the shared C-ABI arm would **change the
  convention a C function uses on those targets**. That is an ABI change with a
  behavioural gate, not a no-op deletion, and it is entangled with the
  `and (not CProgramMode)` guards on the aarch64/arm32 call arms that currently
  compensate for exactly this table.

Per this ticket's own gate language — *"if it does [change bytes], that
divergence is the real finding and deserves its own ticket"* — the remaining
targets are that separate ticket. The convention table in the UPGRADED section
above is its statement of the problem; what it needs is a gate that asserts the
new behaviour rather than byte-identity, plus removal of the compensating guards
in the same change.

Filing it as `bug-c-a-c-function-s-calling-convention-depends-on-the-target`
rather than silently widening this one.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
