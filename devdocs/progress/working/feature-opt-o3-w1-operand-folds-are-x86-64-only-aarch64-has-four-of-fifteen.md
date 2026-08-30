---
prio: 55
track: A
status: working
owner: frank-optimize-b4
---

# -O3: the W1 operand folds are x86-64-only — aarch64 has 4 gate sites to x86-64's 15

Found by applying face 118's corollary — **count arms by parsing, not by
reading** — to this campaign's own per-target chain, after the coordinator
flagged that the xtensa managed-cleanup arm released 1 kind where every other
arm released 7 and nobody noticed for four edits.

- **Type:** feature (codegen — optimization) — **Track O**, file-ownership
  **Track A** (`compiler/ir_codegen_aarch64.inc`). Gate: `make compiler/pascal26`
  plus an `-O0`/`-O3` control pair per ported pass.

## The count, measured

`OptLevel >= 3` gate sites per backend, parsed rather than eyeballed:

| backend | -O3 gate sites |
| --- | --- |
| `ir_codegen.inc` (x86-64) | **15** |
| `ir_codegen_aarch64.inc` | **4** (a 5th match is prose) |
| `ir_codegen386` / `_arm32` / `_riscv32` / `_xtensa` | 0 each |

The four zeros are **correct and deliberate** — CLAUDE.md scopes per-backend
effort to x86-64 + aarch64, because 32-bit is perf-irrelevant and ESP/xtensa's
hot paths are hardware peripherals. This ticket is only about the second row.

### CORRECTION 2026-08-30 (slice 10): the count above undercounts BOTH rows

The grep was `OptLevel >= 3`. Roughly a fifth of this campaign's gates are
spelled `if OptLevel < 3 then Exit;` — an early return at the top of a
predicate, which is what slices 7, 8 and 10 all use — and that spelling is
invisible to it. Parsing **both** spellings:

| backend | `>= 3` | `< 3` | total |
| --- | --- | --- | --- |
| `ir_codegen.inc` (x86-64) | 17 | 6 | 23 |
| `ir_codegen_aarch64.inc` | 5 | 2 | 7 |
| the other four | 0 | 0 | 0 |

How it surfaced: slice 10 added a gate and the `>= 3` count did not move — 17
before, 17 after. That only shows up because the umbrella takes the count every
slice. **"Count arms by parsing, not by reading" buys nothing when the parse
matches one of the two ways the arm is written**; the instrument needs the same
adversarial pass as the finding.

### …and 23 : 7 was wrong too. The number of record is 22 : 6

A raw grep counts prose. Each of those two files carries exactly one
CONTINUATION line inside a `{ ... }` comment block that mentions a gate in
passing — `ir_codegen.inc:4434` and `ir_codegen_aarch64.inc:1280` — and neither
starts with a comment marker, so no per-line test removes them. This ticket's
ORIGINAL count already carried the footnote *"4 (a 5th match is prose)"*, which
was the tell and was read as a footnote rather than as a defect in the method.
Comment-stripped, the counts are **x86-64 22, aarch64 6**.

Three counts, three wrong answers, and every one was the instrument rather than
the thing measured: 15 : 4 missed a spelling, 23 : 7 counted comments, and only
the third needs no asterisk. The ticket's conclusion never moved through any of
it — the gap is real and if anything wider than first reported. That is exactly
what makes it dangerous: **a finding whose supporting number keeps changing
while its direction holds is one nobody re-checks.**

### The count is now an assertion, not a command

`tools/check_o3_backend_parity.py`, wired as a step in `gate.sh quick` (under a
second, same placement and same rationale as `check_no_vendor_tracked.sh` — an
invariant only a nightly notices cannot stop a push). It:

- comment-strips the source (`{ }`, `(* *)`, `//`, string literals) before
  matching, so prose cannot inflate the count;
- matches **every** spelling of an `-O3` gate — `>= 3`, `> 2`, `< 3`, `<= 2`,
  `= 3`, with or without spaces — which is the first correction made permanent;
- derives the backend list from `compiler/ir_codegen*.inc` by glob, so a seventh
  emitter added later inherits the check (expected 0) instead of escaping it;
- freezes **22 : 6**, and prints every match with file and line under
  `--census`, so a reviewer can check the number rather than trust it.

It does **not** forbid a one-armed slice — most legitimately are, since an
x86-64 encoding often has no one-to-one aarch64 spelling. It forbids a one-armed
slice **nobody noticed was one-armed**: widening the delta is now an edit to
that file, in the same commit, visible in the diff, with the two honest
resolutions spelled out in the failure message.

Verified by breaking it three ways: adding one `-O3` gate to the x86-64 emitter
fires it; adding a *prose mention* of a gate does not; and a new
`ir_codegen_*.inc` file carrying a gate is reported as unfrozen rather than
ignored.

The slug still says "four-of-fifteen". Slugs are cited by resolved commits and
by the board, so it is **not** renamed; this section is the correction of
record, and the assertion is the thing to trust.

**A gate count is not a pass count**, and this ticket does not claim eleven
missing passes — several x86-64 sites gate arms of one pass, and some are
instruction encodings with no one-to-one aarch64 spelling. Counting the
population to choose a target and counting firings to claim a result are
different jobs (umbrella standing rule 2). What the count *does* establish is
the shape: one arm of a two-arm chain has been extended eight times and the
other twice.

## What aarch64 has, and what it does not

Has: `UnifiedResidencyAssignA64` (the W2 residency keystone — its guard set was
compared against x86-64's by parsing and has **not** drifted: 11/11 `Continue`
guards and 7/7 `Exit` guards match one-for-one, the only differences being the
target check and the register-pool bound `islot >= 6` vs `islot >= nFree`),
`W2InPlaceEligibleA64`, and const/`LOAD_SYM` right-operand folds.

Does not have the **W1 slice 5-8 family**:

- slice 5 — a register-resident left operand feeding a compare, read in place
- slice 6 — resident left times a constant via three-operand multiply
- slice 7 — the compare's **right** operand read in place (register or frame slot)
- slice 8 — both operands 4-byte, folded as a narrow compare
- the last-call-argument push/pop collapse

Every one of these is a *concept* that aarch64 can express (it has three-operand
arithmetic natively, and `cmp` against a register is its normal form); none is a
transliteration of an x86-64 encoding. So the port is real work, not a rename —
which is exactly why it has not happened by accident.

## Why this is worth a ticket rather than a note

The umbrella *states* aarch64 is in scope. Nothing measured whether it was, and
"aarch64 is in scope" and "aarch64 got 4 of 15" are consistent statements —
which is the trap. Co-location did not save the xtensa arm either
(`0f48fa6a9` gathered six per-target blocks into one procedure specifically to
stop drift, and i386 and riscv32 were then extended four times, twenty lines
from xtensa's one-row arm). **Seeing that an arm is short and being made to care
are different events**, so the remedy is a recurring count, not a better comment.

**Standing suggestion for this campaign:** every future W1/W2 slice records its
per-backend gate count in the umbrella's log, parsed. It is one command and it
is the only thing that would have caught this.

## Gate

Per-pass, as everything in this campaign: `-O3`-gated, its own `-O0`/`-O3`
control pair against one expectation, band rows (adjacent values, not far-apart
memorable ones — standing rule 4), and a deliberate break verified to change the
**emitted bytes** rather than merely the source. Cross-check aarch64 output under
qemu against the x86-64 result for the same program.

## Links

- Umbrella: `feature-opt-o3-register-pressure` (W1/W2, and its "Target scope"
  section is the claim this ticket measures)
- Same shape, different chain: the xtensa managed-local cleanup arm (1 kind
  released where the others release 7)


## LANDED 2026-08-30: slices 5 and 7, as ONE arm

Baseline compiler `a60f92ba830a`, new `0d4f0b2a4ceb` — both built at the same
HEAD, the baseline being HEAD with only this hunk reverted.

`cmp Xn, Xm` on aarch64 **is** `subs xzr, Xn, Xm`: both sources are free
register fields. So the two x86-64 slices collapse into one arm here — a
resident LEFT and a resident RIGHT are each read where they live, and both
staging moves disappear. x86-64 needed slice 5, then slice 7, then slice 8's
memory form, to say what one encoding says on aarch64. **The port was not a
transliteration and it was not a rename; it was smaller than either.**

**Measured (aarch64, -O3, output identical, `-O0`/`-O1`/`-O2` byte-identical):**
`test_cmp_right_in_place` **-1072 bytes**, `bench/w1_three_locals` **-988**,
`lispdemo` **-3604** — 901 instructions deleted in lispdemo alone. x86-64 output
is byte-identical at every level, as it must be: the pass lives entirely in
`ir_codegen_aarch64.inc`.

This is also, incidentally, the highest-leverage single arm available on this
backend, for a reason worth recording: **aarch64 has no fused compare-and-branch
path.** A conditional jump evaluates the comparison into x0 through this same
generic arm and then tests it, so every loop condition in every program goes
through the code this slice just shortened. x86-64 has a separate fused-jump
path and needed both halves wired.

### `CmpFusible` is shared, not copied

The cross backends are included BEFORE `ir_codegen.inc`, so the predicate is
forward-declared in `compiler.pas` — two lines below `IRNodeOwnsManagedStr`,
which is forwarded for exactly the same reason and carries the reason in its
comment: four cross backends each hand-rolled a narrower copy of a shared
predicate and **every one of them was wrong**. A second definition of "which
comparisons reach the bare cmp" would be that bug waiting.

### The scope guard is about SIZE, not correctness — and I had the reason wrong

The fold is restricted to the const-right and leaf-sym-right arms. I wrote that
the general arm was excluded because "a left value that was never materialised
cannot be pushed across an arbitrary right subtree". **That is false**, and
removing the guard on purpose left every test GREEN, which is what sent me to
measure instead of assert.

- The pushed x0 is dead: the cmp reads the home register, so popping garbage
  into x0 harms nothing.
- The real candidate hazard is reordering — `a < f()` where f writes `a` would
  read the NEW value at cmp time. **That cannot happen**: a local reachable
  through a nested procedure or a `var` parameter is marked `escapes` by the
  residency assigner and never gets a register at all. Verified both routes
  with `PXXDBG=a.resid` — the mutating probe's `a` shows `escapes` and no
  `ASSIGN` line.

So the fold is correct in that arm too, and the exclusion is temporary: folding
there while keeping the `str`/`ldr` saves one instruction and leaves two dead
ones, where doing it properly drops the whole staging for three. Different
shape, own control pair, own commit —
`feature-opt-o3-a64-fold-a-resident-compare-left-across-a-complex-right`.

**A break that is NOT caught is a finding.** Three of the four deliberate breaks
moved `-O3` while `-O0` and x86-64 stayed correct: a wrong Rn field gives
`acc=0` (every comparison false), a wrong Rm field `acc=42876`, and an unfolded
right defaulting to x0 instead of x1 produces no output at all. The fourth —
widening the scope guard — was **not** caught, and chasing that rather than
recording three-out-of-four is what produced the two paragraphs above.

### Per-backend gate count: x86-64 22, aarch64 **7** (was 6)

First real use of `tools/check_o3_backend_parity.py`, and it fired in the good
direction — the gap closing, not widening. Bumped in the same commit, which is
the workflow the assertion exists to force.

### Still not ported

Slice 6 (resident left times a constant, three-operand multiply — aarch64 has
`madd`/`mul` natively and no imm form, so this needs a different shape), slice 8
(the narrow 32-bit compare — `cmp Wn, Wm` exists and should be a small
follow-on), and the last-call-argument push/pop collapse. The ticket stays open
for those.


## Slice 8 on aarch64 is worth ZERO — measured, not ported

The next item on the list was slice 8, the narrow 32-bit compare. **It has no
aarch64 analogue with a win, and the right answer was not to write it.**

`cmp Wn, Wm` and `cmp Xn, Xm` are both one four-byte instruction, so the width
itself buys nothing. What slice 8 actually bought on x86-64 was the **memory**
form — dropping REX.W is what made `cmp rNd, [rbp+d32]` legal, folding a frame
slot into the compare. aarch64 has no memory operand for `cmp` at all, so the
half that paid has nothing to port.

Measured rather than argued, because "both encodings are one instruction" is the
kind of claim that is right for the wrong reason often enough to check. Programs
identical but for `LongInt` vs `Int64` operands, at `-O3` on aarch64, over a
loop of N compares:

| compare rows | 32-bit | 64-bit | delta |
| --- | --- | --- | --- |
| 3 | 130228 | 130220 | 8 |
| 9 | 130348 | 130340 | 8 |
| 27 | 130708 | 130700 | 8 |

**The delta is constant.** A narrow operand costs 8 bytes once — two `sxtw` at
residency init — and **zero per compare**. Varying the row count is what turns
"32-bit code is slightly bigger" from a number that looks like a per-compare
cost into one that is provably not: a single measurement at 3 rows would have
read as "8 bytes of slack, go get it".

A pass that fires and saves nothing is worse than no pass: it is more code, more
risk, and it would have grown the aarch64 gate count — *closing the parity gap
numerically while buying nothing*, which is precisely the number-versus-
conclusion drift this ticket's own three wrong counts were about.

## Slice 10's twin ported instead — the leading widen

Baseline `d89206e1b8de`, new `8ba8a81efea0`, both at the same HEAD with the
baseline being HEAD minus only this hunk.

aarch64's shift arms open with the same leading widen x86-64's do — `sxtw x0,
w0` for a signed native-width result, `mov w0, w0` to zero-extend — preceded by
`mov x0, xN` when the operand is resident. `sxtw x0, wN` and `mov w0, wN` each
do the read AND the extension in one instruction.

**Both flavours fuse here, and only one does on x86-64** — slice 10 fused the
`cdqe` and left `mov eax, eax` alone. Writing the aarch64 helper with a
two-valued result made that asymmetry visible; filed as
`feature-opt-o3-fuse-the-resident-read-into-the-zero-extend-too-x86-64` [p45].
**Porting a pass is a second reading of it, by someone who has to state its
shape in a different language.**

**Measured (aarch64 -O3, output identical, -O0/-O1/-O2 byte-identical, x86-64
byte-identical at every level):** `test_shr_resident_widen` −24 bytes (6
firings), `bench/w1_three_locals` −4 (1); `lispdemo` and
`test_cmp_both_in_place` unchanged, no firing. Small — the population is shifts
of a resident narrow, not compares — and it is the same instruction the x86-64
twin deletes.

**Non-vacuity:** three deliberate breaks — a wrong Rn in the `sxtw`, a wrong Rm
in the zero-extend form, and the widen site ignoring the deferred load (so x0 is
never loaded) — each move aarch64 `-O3` while `-O0` and x86-64 stay correct,
to three different wrong answers.

### The aarch64 test rows were ZERO coverage and looked like a row

Caught by the coordinator off twatch, not by me. The `for`-loop rows I added for
`test_cmp_both_in_place` used `$$$$(...)` where a make recipe needs `$$(...)`,
so the shell saw `$$` — its own PID — followed by a literal `(printf ...)`. Both
sides of the comparison were command *strings*, never program output, and could
never have matched.

The failure mode is the one this ticket already banked in the other direction: a
deliberate break that passes is a wrong claim about your code, and **a row that
fails for a reason unrelated to what it tests is equally uninformative — had the
two strings happened to agree, it would have been a green row proving nothing
about 901 deleted instructions.**

Repaired and then *proven*, which is the part worth copying: the recipe block was
extracted into a scratch makefile so real `make` did the `$$` expansion, run
green, then run again with **only the aarch64 expectation** perturbed by one
digit — it fails there, on `acc=49149` from the qemu run, which is proof the
comparison now reaches the program. Same treatment applied to the new
`test_shr_resident_widen` aarch64 rows before trusting them.

### Per-backend gate count: x86-64 22, aarch64 7 -> **9**

### Remaining

Slice 6 (resident left times a constant) is the last of the family, and it is
**a different shape, not a port**: aarch64 has no `imul`-immediate form, so
there is no three-operand encoding to fold into and the constant needs
materialising into a register first — which is what the const-right arm already
does. It should be reassessed on its own merits, and the slice-8 result above is
the reason to measure before writing. The last-call-argument push/pop collapse
is untouched and is genuinely a port.
