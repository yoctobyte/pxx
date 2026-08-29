---
prio: 65
track: A
status: backlog
owner: ""
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
