---
track: A
prio: 50
type: bug
status: done
found: 2026-08-30
found-by: claude-A
owner: claude-A
---

# The cdecl soundness reject still has its argument-shaped door on i386/arm32/aarch64/riscv32

`bug-a-a-cdecl-procaddr-passed-as-an-argument-escapes-the-sysv-soundness-reject`
closed the **x86-64** half of this, by making the binding genuinely sound there
(`feature-cdecl-bodied-sysv-prologue`) rather than by fixing the guard. The guard
itself was never made shape-complete, and on the four targets that still need it
the door is exactly as open as it was.

Measured on aarch64 at slice 1, `82c135761`+slice-1:

| shape | aarch64 |
| --- | --- |
| `p := @MyCb; p(2.5, 7)` | refused: `... not C-callable yet` |
| `Take(@MyCb)` (argument) | compiles clean, prints **0** (want 9) |

Same source, same line numbers, one refused and one silently wrong.

## Why it was not fixed with the x86-64 half

The reject is keyed on `AN_ASSIGN` whose RHS is `AN_PROCADDR`. Making it
shape-complete means moving the check to wherever an `AN_PROCADDR` is coerced
INTO a location of `cdecl` proc type — and that is more than one more shape:

- a call argument bound to a `cdecl` proc-type formal (the measured hole)
- a record field or array element store
- a function `Result` of proc type
- a `const`/initialised variable declaration

Enumerating shapes is what produced this bug in the first place. The fix that
actually closes it is a single coercion chokepoint that both the assignment path
and every other path funnel through, which is a design question and not a
condition edit. `devdocs/dev/normalise-dont-special-case.md` is the relevant
doctrine: the second path is the one that stays broken, and there are currently
five.

## The other fix, which may be the better one

Give the four targets a real C-convention prologue arm, the way x86-64 now has
one (`EmitParamSpillsForTarget`'s `ProcCdecl` arm). Then the reject is obsolete
everywhere and gets deleted rather than repaired, and no shape enumeration is
needed at all. AAPCS64 and AAPCS32 both count integer and FP registers
independently, so the shape of the x86-64 arm carries over.

> **The riscv32 half of that sentence was wrong and is corrected below** (see
> "riscv32 is ILP32 SOFT-float"). It originally read "riscv32's ILP32D does
> too". pxx's riscv32 has no FP register bank at all, so the x86-64 arm's shape
> carries over to riscv32 *not at all* — and by the time this was caught the
> claim had already been repeated back to me by the coordinator, which is how a
> premise in a ticket becomes a premise in a design.

**This is the root-cause option and it closes the ticket by deletion.** Measure
tickets-closed-per-change, not lines touched: repairing the guard leaves the
underlying inability in place on four targets forever, and a repaired guard is
still a guard someone must keep shape-complete.

## Gate

On each of i386/arm32/aarch64/riscv32, under qemu: `Take(@MyCb)` with a
by-value float param and with >6 integer params either produces the correct
value, or is refused — never a wrong value. The x86-64 rows of
`test/test_cdecl_bodied_sysv.pas` become cross-target rows if the prologue
option is taken.


---

# PROGRESS (2026-08-30)

| target | arm | left the reject | notes |
| --- | --- | --- | --- |
| x86-64 | done | done | `feature-cdecl-bodied-sysv-prologue` |
| aarch64 | done | done | AAPCS64, independent x0..x7 / d0..d7 banks |
| arm32 | done | done | AAPCS soft-float; **half-joined**, see below |
| i386 | done | done | cdecl argument ORDER; no float mechanism involved |
| riscv32 | **none needed** | done | its convention already IS the C convention — see below |

**i386's mechanism was a third one, and no earlier case could see it.** x86-64
and aarch64 diverged on independent register banks; arm32 on 8-byte alignment.
i386 has neither — it passes everything on the stack in one sequence — and
diverged purely on ORDER: cdecl puts arg0 at the lowest address, pxx's internal
convention pushes left-to-right and leaves the leftmost argument deepest. Its
discriminating case is `f(1, 2, 3)` returning `a*100 + b*10 + c`, which printed
**321** pre-arm on i386 and 123 on every other target. Three DISTINCT integers
are load-bearing: every other case in the narrow file passes an equal or
nil-shaped argument somewhere, and a reversed argument list is invisible under
those. That is now three targets in a row whose mechanism was invisible to the
previous target's case, which is the evidence behind the riscv32 note below.

**arm32 half-joins.** Its arm is correct for every signature it accepts and it
refuses any argument block over 4 core registers, because stack arguments are
unimplemented on both sides of the call there —
`bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area`. Ordinary Pascal such as
five integer params is in the refused set. Saying "arm32 is done" without that
sentence would be false.

## The slicing is also the census, and that is why it is per-target

Sliced per target for bisectability. It turned out to be the only reliable way
to FIND the instances, which is a stronger argument and the one that should
survive the next person who wants to do all four at once.

**Each target diverged by a different mechanism, and each needed a
discriminating case built from its own ABI:**

- x86-64 / aarch64 — independent integer and float register banks. Discriminated
  by a MIXED signature: `f(i1,d1,i2,d2,i3,d3)`.
- arm32 — armel is SOFT-FLOAT and has no float bank at all. The mixed case is
  meaningless there. It diverges on 8-byte ALIGNMENT: `f(a: Integer; b: Double)`
  must skip r1 and land the double in r2:r3. Measured 7, want 9.

The other targets' discriminating case ALREADY PASSED on arm32 —
`f(a: Double; b: Integer)` gave the right answer, because soft-float coincides
with positional when the double is first. **A correct test pointed at the wrong
ABI reports a false green**, and reusing it would have shipped an arm nothing
tested. riscv32 passing all 12 narrow checks today is that same reading and must
be treated as mute, not clean.

## One predicate, four targets, four symptoms, and a census that cannot see it

"A by-ref parameter is a POINTER and classifies as one" is implemented
independently per backend, and was wrong in every one reached so far:

| target | symptom |
| --- | --- |
| x86-64 | pointer passed in xmm — segfault |
| aarch64 | pointer in the FP bank — segfault |
| arm32 | sized 8 bytes and 8-aligned instead of one word — block desync, segfault |

**A grep census does not find these.** `TypeIsFloat(Procs[` reports arm32 clean:
arm32 spells the rule as `tk = tyDouble` / `tk = tyExtended` against a local,
with no `TypeIsFloat` call near it. arm32 was fixed only because the alignment
work required reading that file line by line.

The count "4 sites across 4 backends" is *self-consistent* and still wrong — the
denominator came from the same grep. **An arithmetic cross-check only works when
the denominator comes from OUTSIDE the instrument** (`ls compiler/ir_codegen*.inc`
gives 7). Treat any grep count of this predicate as a lower bound.

So: **read i386's and riscv32's classification line by line; do not grep for it.**
The per-target slicing forces exactly that, which is why the remaining two will
surface their own instances regardless of who is paying attention.


## riscv32 is ILP32 SOFT-float, and its divergence is at TEN words (2026-08-30)

**The ILP32D premise above is wrong, measured three independent ways.** pxx's
riscv32 has no floating-point register bank in the parameter path at all:

- a riscv32 binary carries `e_flags = 0x0` = `EF_RISCV_FLOAT_ABI_SOFT` (`0x4`
  would be double);
- there is not one f-register anywhere in `ir_codegen_riscv32.inc`, and float
  conversion goes through `FindProc('__pxx_i2s')` — a *call* into soft-float
  emulation;
- every multilib of the installed `riscv32-esp-elf-gcc` 15.2.0 is `mabi=ilp32`.

A by-value `Double` is therefore **two integer words** in `a0..a7`, exactly as
`EmitParamSpillsForTarget`'s riscv32 arm counts it.

**So riscv32 passes all 12 narrow checks HONESTLY, not by luck, and the green
means something after all — just not what it looked like.** All three earlier
mechanisms are genuinely absent here. There are no independent banks to
desynchronise (x86-64/aarch64). There is no even-register alignment rule: the
RISC-V psABI deliberately does *not* require it, unlike AAPCS32, so `f(Integer,
Double)` packs into `a0`, `a1:a2` — verified against gcc, which emits exactly
that. And word *k* goes to `a[k]` leftmost-first, so there is no order flip
(i386). For everything that fits in the eight argument registers, pxx's riscv32
convention already **is** the C convention.

**The divergence is the stack tail, and it starts at TEN words.** pxx places
overflow word *k* at `[entry_sp + (pnWords-1-k)*4]` — *descending*. The psABI
puts the first overflow word at `sp+0` and counts up. Measured against
`riscv32-esp-elf-gcc` 15.2.0, `-march=rv32imc_zicsr_zifencei -mabi=ilp32`, from
both sides so the reading is not one interpretation twice:

| ten int params | word 8 (`i`) | word 9 (`j`) |
| --- | --- | --- |
| gcc caller places | `0(sp)` | `4(sp)` |
| gcc callee reads (`-O1`) | `0(sp)` | `4(sp)` |
| **pxx callee reads** | **`20(s0)` = entry_sp+4** | **`16(s0)` = entry_sp+0** |

Reversed. pxx's *caller* is reversed to match — not separately disassembled, but
forced: the callee provably reads word 8 from entry_sp+4, and pxx↔pxx returns
the right answer, so pxx's caller must write it there. Hence C interop is broken
in **both** directions on riscv32 at ten or more words, while Pascal↔Pascal is
fine because both ends share the mistake.

**NINE words is a trap, and it is the probe I would naturally have written.** At
exactly nine words there is a single overflow word and `(pnWords-1-k)*4` =
`(9-1-8)*4` = `0` — the descending formula and the ascending psABI *coincide*.
A nine-argument probe returns a clean green. I ran that probe first and it
passed; the bug is only visible from ten. Same shape as the split-double corner
(seven ints then a `Double`: low half in `a7`, high half at entry_sp+0, which
gcc does and pxx's formula also produces — nine words again, so again a
coincidence rather than agreement).

**The consumer is real.** `--emit-obj` exists for `--target=riscv32|xtensa`
specifically so ESP-IDF C can call pxx-emitted code, which is the whole point of
Track S. This is not a hypothetical observable.

**xtensa was NOT measured** and must not be assumed to share this. It has the
same zero-oracle-adoption property and no case has been built for it.


## riscv32 needed no arm — the convention fix WAS its arm (2026-08-30)

Target 4 closed differently from the other three, and the empirical check was
worth running rather than assuming: the reject was lifted for riscv32 first, and
then everything was measured.

**No prologue arm, no admission change, no call-form change.** `ProcCdecl` is
deliberately NOT set for riscv32 in `pasparser_proc.inc`, and that absence means
something different from xtensa's. xtensa lacks an arm. riscv32 has nothing for
the flag to *select*: after
`bug-a-riscv32-passes-stack-arguments-in-reverse-psabi-order` its ordinary
convention is the C convention at every width — word *k* in `a[k]`, no FP bank
to count separately (ILP32 soft-float), no even-register alignment rule, and the
overflow tail in psABI order. Setting the flag would assert a distinction the
target does not have.

Measured with the reject lifted: `CDECL-NARROW OK checks=12` on riscv32,
assignment shape included, and `CDECL-WIDE OK checks=3` at ten words in all
three shapes.

### The ten-word file, and why it is not redundant

`test_cdecl_bodied_wide.pas` cannot go in the narrow file (arm32 caps that at
four words) and runs only on x86-64, i386 and riscv32 — aarch64 and arm32 refuse
a >8-word signature outright.

It asserts pxx-caller↔pxx-callee agreement, which **passed before the convention
fix too**, because both ends shared the error. So it is not a proof of
conformance — that was established by disassembly against
`riscv32-esp-elf-gcc` 15.2.0 — it is a guard against the five sites **drifting
apart**, which is this fix's actual failure mode.

**Mutation-tested rather than claimed.** Reverting the reordering at one of the
five sites (`IR_CALL_IND`, the shape a C function pointer takes) and rebuilding:

```
FAIL ten words via fnptr:               got 1234567909 want 1234567900
FAIL ten words via assigned variable:   got 1234567909 want 1234567900
CDECL-WIDE FAILURES=2
CDECL-NARROW OK checks=12      <- the narrow file does NOT notice
```

`1234567909` is exactly words 8 and 9 swapped. The direct-call shape stayed
green because `IR_CALL` was not the mutated site, so the three shapes are
independently covered. And the narrow file passing throughout is the evidence
that the new file earns its place.

### Where the campaign leaves the reject

All four campaign targets are out. What remains behind it is **xtensa** and
wasm32, neither of which was ever in scope, and the argument-shaped door is
still open for them — the reject is still keyed on the `AN_ASSIGN` shape and a
`@proc` passed as a call *argument* still walks past it. That was true when this
ticket was filed and it is still true for the targets that remain.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
