---
prio: 55
track: A
status: backlog
owner: ""
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
