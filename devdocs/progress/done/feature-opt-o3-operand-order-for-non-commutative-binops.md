---
prio: 65
track: A
status: done
owner: frank-optimize-b4
---

# -O3: evaluate a non-commutative binop's operands right-first when the right is pure

Split out of `feature-opt-o3-register-pressure` (W1). Item **(C)** of three found
by disassembling that campaign's benchmark loop, and the largest at **−2
instructions**. Filed separately because it is a different *kind* of work from
the encoding folds that make up W1 slices 5-8 — it is the emit-time **operand
scheduler** the umbrella names in its own charter, and it should be dispatchable
without holding the umbrella.

- **Type:** feature (codegen — optimization) — **Track O**, file-ownership
  **Track A** (`compiler/ir_codegen.inc`). Gate: `make compiler/pascal26` (the
  byte-identical self-host fixedpoint) plus the repro.
- **Worth:** −2 instructions per occurrence, in the inner loop.

## The observation

`three.pas`, `acc := acc + j - (i shr 1)`, at `-O3`, HEAD `989e45c01`. The
subtraction's operands:

```
  88:  4c 89 f8        mov    rax,r15     ; acc
  8b:  4c 01 e8        add    rax,r13     ; + j       -> left operand ready in rax
  8e:  49 89 c0        mov    r8,rax      ; ... staged OUT to r8
  91:  4c 89 e0        mov    rax,r12     ; i
  94:  48 98           cdqe
  96:  48 c1 e8 01     shr    rax,0x1     ; i shr 1   -> right operand, in rax
  9a:  48 89 c1        mov    rcx,rax     ; ... moved to rcx
  9d:  4c 89 c0        mov    rax,r8      ; ... left operand restored
  a0:  48 29 c8        sub    rax,rcx
```

The left operand is computed first, evicted to r8, and restored — purely because
the right subtree also wants rax. Evaluating the **right** subtree first, into
rcx, then the left into rax, removes `mov r8,rax` and `mov rax,r8` outright.
`sub rax, rcx` is unchanged: the operands still land in the registers the
existing emitter expects.

## Why this is not the -O2 mirror already in the file

There is already a mirror at the `IR_BINOP` and fused-compare sites, promoted to
`-O2` on 2026-07-11. It **swaps** the operands, so it applies only where swapping
is semantically free — commutative ops, or a compare whose predicate can be
inverted. `sub` is neither. This item swaps the **evaluation order** while
keeping the **operand roles** fixed, which is a different transformation with a
different legality condition, and it is the one that covers `-`, `shr`, `shl`,
`div`, `mod` and string/pointer differences.

## Legality

Reordering evaluation of two operands is observable exactly when both can have
effects. The condition is the one the file already has: the subtree evaluated
first must be side-effect-free with respect to the other — `ScratchSafeSubtree`
is the existing predicate at the neighbouring `-O2` mirror site, and the same
reasoning applies (`InLValueWrite` must also be respected).

**Be stricter than "no calls".** The umbrella's own history has the worked
example: `ForBoundReEmittable` was written as a closed allow-list defaulting to
**FALSE** rather than a deny-list, because a deny-list is wrong the first time
someone adds an AST kind. Do the same here. And note the failure mode is an
*ordering* change, so a test that counts calls or iterations cannot see it — the
`test_for_init_temp_elision` control was vacuous for exactly this reason until it
logged call **order** (`iL` vs `Li`). Any control test for this item must observe
order, not counts.

## Gate

`-O3`-gated. Own `-O0`/`-O3` control pair against one expectation (standing rule
1 — the fixedpoint gate cannot see an `-O3`-only defect). Rows must include:

- a non-commutative op where both subtrees are pure (the win case);
- one where the right subtree **calls** something that mutates a variable the
  left subtree reads — with the call **order logged**, so a swap is visible;
- an lvalue-write context, which must decline.

Non-vacuity: break the ordering on purpose and confirm the order log moves.
Verify the injected break changes the emitted bytes, not just the source.

## Scope note

Per the umbrella: per-backend effort is **x86-64 and aarch64 only**. This is an
emit-time decision in the x86-64 emitter; the aarch64 emitter has its own
operand staging and should be assessed separately rather than assumed to share
the shape.

## Links

- Umbrella: `feature-opt-o3-register-pressure` (W1 — "emit-time operand
  scheduler" is this item)
- Sibling split out at the same time: `feature-opt-o3-fuse-resident-read-and-widen-into-movsxd` (item B, worth −1)
- Together with (B): the `three.pas` loop goes 18 -> 15 instructions.


## 2026-08-30 — LANDED behind -O3, and the ticket's own -2 was wrong

**Worth -1 instruction, not -2.** The estimate above was made by reading a
disassembly and counting the two moves that looked removable; writing the pass
showed why only one of them is.

The obvious version — right into rcx, then left into rax — is **unsafe**.
`ScratchSafeSubtree` does not promise rcx is untouched: its whitelist explicitly
admits emissions using rax/rcx/rdx, and a nested BINOP loads its own right
operand into rcx. Emitting left after setting rcx would clobber it. That version
is safe only for a LEAF left, which is exactly the case the `-O2` mirror already
takes — so what remains is the both-complex case, and there the win is one move.

The safe form parks the **right** value instead of the left: park, emit left
(which lands in rax where it belongs), then move rcx straight from the scratch
register. Three moves become two; the restore disappears.

**Legality is stricter than this ticket assumed.** The arm below needs only
`ScratchSafeSubtree(right)` because it evaluates left FIRST. Reversing the order
needs **both** sides pure — a left with side effects must not be moved after a
right that can read them. That is not a belt-and-braces guard, it is the guard:
dropping it is the pass's real failure mode, and the test catches it.

**Result:** `three.pas`'s loop 18 -> **17** instructions. Campaign cumulative on
that loop: **22 -> 17**.

Controlled A/B at HEAD, baseline = HEAD with only this hunk reverted (new
`ee260a116022`, base `3b567373c1ef`, both 1 round). All six byte-identical at
-O0/-O1/-O2; -O3 smaller on all six:

| program | -O3 base -> new |
| --- | --- |
| `perf/three.pas` | 18590 -> 18557 (**-33**) |
| `bench/portable/mandelbrot.pas` | 25137 -> 25107 (**-30**) |
| `examples/mandelbrot/mandelbrot.pas` | 122534 -> 122345 (**-189**) |
| `examples/lisp/lispdemo.pas` | 105587 -> 105461 (**-126**) |
| `examples/json/jsondemo.pas` | 446736 -> 446085 (**-651**) |
| `examples/primes/sieve.pas` | 86511 -> 86406 (**-105**) |

**Per-backend gate count** (the umbrella's new standing rule): x86-64 **16**,
aarch64 **4**. This slice widened the gap by one, on the arm that was already
ahead — recorded rather than excused; see
`feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen`.

**Non-vacuity.** Two deliberate breaks, both moving -O3 while -O0 stays correct:
dropping the left-purity guard gives `leftimp=52` instead of 51, and mismatching
the scratch register gives `pure=1007` and a truncated call log. The first is the
one the ticket demanded — **and it only works because the value straddles a `shr`
boundary.** An earlier draft used gV=100, where `100 shr 1` and `101 shr 1` are
both 50, and the unsafe build passed. Standing rule 4 is about adjacency, and it
applies to an ORDERING exactly as it does to a register: the reordered read must
differ from the correct one, and round numbers are where it does not.
## Log
- 2026-08-30 — resolved, commit bcecdfab3.
