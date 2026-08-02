---
track: A
prio: 58
type: feature
summary: "The register-value scaffold two -O passes are blocked on: a single choke point for every write to the accumulator, so a 'rax currently holds symbol S' fact can be maintained without a silent-miscompile risk. Today rax is written from hundreds of scattered raw EmitB sites."
---

# An accumulator value tracker — the scaffold `-O` passes keep waiting for

- **Type:** feature (codegen infrastructure) — **Track A** (Track O work)
- **Filed:** 2026-08-03, splitting the blocker out of
  [[feature-opt-store-reload-elimination]] so it can be ranked on its own.

## Why it exists as its own ticket

`feature-opt-store-reload-elimination` has sat in `backlog/` since 2026-07-03
with "BLOCKED on a register-liveness scaffold" in its body but **no
`blocked-by:` field**, so `progress.sh ready` has been offering it as pullable
work the whole time. It is not pullable: landing it without this scaffold means
a tracker that can believe a stale value, and that is a SILENT MISCOMPILE — the
one outcome this repo will not trade speed for.

The blocker was also worth re-checking rather than inheriting.
[[feature-callconv-register-args]] is now **done**, and its write-up mentions
liveness — but what it actually built is measurement (`InlineMeasureBody`,
`RegcallMeasureBody`: makes-a-call, early-exit, addr-taken-param counters over
the IR). Useful, and not a value tracker. **The blocker is real and unchanged.**

## The problem, precisely

The win is ordinary:

```pascal
x := a + b;    { mov [rbp+xoff], rax }
y := x * 2;    { mov rax, [rbp+xoff]   <- rax already holds it }
```

The reason it cannot be taken today is that correctness needs the tracker
INVALIDATED the instant anything writes rax, and rax is written from hundreds
of scattered raw `EmitB($48); EmitB($B8); ...` sites across `ir_codegen.inc`
with no choke point. Miss one and the tracker hands out a stale value.

The concrete case that killed the naive attempt, worth keeping in front of
whoever picks this up: `y := 5 * x` evaluates the CONST left leaf first
(`MovRaxImm(5)` clobbers rax) and only then reaches `IR_LOAD_SYM(x)`. A tracker
that knows only "rax held x after the store" skips the load and multiplies by 5.

## Shape A — route every accumulator write through primitives. RULED OUT.

The obvious design, and the one the parent ticket suggests: funnel every rax
write through `AccumClobber` / `AccumHolds(sym)` so the fact can only change in
one place. `MovRaxImm` already is such a primitive; `EmitLoadVar`, the
arithmetic emitters, the call sequences and the prologue/epilogue are not.

**This collides with a standing policy** (`feedback_asm_emitb_rewrite_policy`):
do NOT run a campaign converting existing raw `EmitB` runs in
`ir_codegen.inc` — conversion is mechanically trivial but every converted block
shifts the emitted bytes, so it is pure reseed / byte-identity regression risk
for zero behavioural gain. Retargeting is opportunistic only, when a block is
being edited and retested anyway.

Shape A IS that campaign, with a silent-miscompile hazard attached if it is
done incompletely. So it is not the route.

## Shape B — decide at the IR level, touch no emitter. PREFERRED.

Make the redundancy decision before codegen and hand the emitter a single bit,
so nothing about how instructions are emitted has to change.

Per basic block (delimited by `IR_LABEL` / `IR_JUMP*`), walk the statement
roots. When root *i* is `IR_STORE_SYM(S, v)` and root *i+1*'s expression tree
would evaluate `IR_LOAD_SYM(S)` **first**, that load is redundant: nothing has
run in between. Mark it, and let `EmitLoadVar` skip a load that carries the
mark.

"Would evaluate first" is the entire correctness question, and it is answerable
exactly: `IREmitNode`'s recursion order is one function, so a small
`IRFirstEvaluated(node)` mirroring it gives the answer without guessing. That
is also precisely what the `y := 5 * x` counter-example tests — there the first
evaluated node is the const leaf, not the load, so the mark is never set and
the reload stands.

The drift risk is that the mirror and `IREmitNode` disagree after a future
edit. Mitigate it the cheap way: the mirror lives next to `IREmitNode` with a
comment on both saying they must move together, and the negative test below is
in the suite permanently. Conservative by construction — anything the mirror is
unsure about is simply not marked, which costs a missed optimisation and
nothing else.

## The invariant to write down

**A load may be marked redundant only when nothing at all is emitted between
the store and it.** Not "nothing that writes rax" — nothing. That is a stronger
condition than the optimisation strictly needs, and it is the one that can be
checked by reading a single basic block instead of by trusting every emitter
site.

## Unblocks

- [[feature-opt-store-reload-elimination]] — the reload the ticket is named for.
- The "dead store to hidden temps" item on [[feature-optimization-levels]] — a
  lowering-time temp written once and read once immediately after can skip its
  frame slot entirely. Same fact, same scaffold.
- Any future peephole that wants to know what a register currently holds.

## Scope note

**x86-64 only, deliberately.** Per-backend register work is x86-64 + aarch64
only by standing policy, and the scaffold should prove itself on one target
before the second. Nothing here changes the IR, so no other backend is touched.

## Gate

- `-O0` self-host byte-identity UNTOUCHED (the scaffold alone changes no
  codegen; it is inert until a pass consults it).
- With the first consumer landed: `make test-opt` differential corpus green —
  same program at -O0 and -O1 producing identical runtime output is the cheap
  oracle that catches exactly this class of miscompile — plus an -O1 self-host
  fixedpoint.
- A deliberate NEGATIVE test: `y := 5 * x` after `x := a + b`, which must still
  reload x. That case is the whole reason the ticket exists and it belongs in
  the suite, not in a comment.
