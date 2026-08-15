---
track: A
prio: 58
type: feature
summary: "The register-value scaffold two -O passes are blocked on: a single choke point for every write to the accumulator, so a 'rax currently holds symbol S' fact can be maintained without a silent-miscompile risk. Today rax is written from hundreds of scattered raw EmitB sites."
status: done
owner: claude-A-N-nightly
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

## Resolution (2026-08-15) — Shape B, landed WITH its first consumer

Built as specified: the decision is made at the IR level and the emitter gets a
single bit, so no raw `EmitB` site moved and the ruled-out Shape A campaign was
never started.

Landed together with the consumer it exists for, behind `-O3`, because a
scaffold nothing reads cannot be tested and the negative case the ticket is
built around only becomes assertable once a mark can be wrong.

**The pieces**

- `IRLoadRedundant` (defs.inc, grown in lockstep with the other node-indexed
  arrays in `EnsureIRCapacity`, cleared per node in `IRAppend`).
- `IRTopLevelStmt` — mirrors `IREmitMachineCode`'s own case label list, so
  "nothing at all was emitted in between" is a scan over node indices: anything
  NOT in that list emits no byte at top level. The three call kinds carry their
  own statement-position flag.
- `ReloadElimSym` — which slots may play: LeafSymRcxLoadable's four tests
  (no float / string / array / by-ref param) restated over a sym index, plus
  ordinal-or-pointer only (a record/set/class/variant destination takes one of
  IR_STORE_SYM's earlier arms, which do not end with rax holding the value) and
  NOT register-resident (`EmitStoreVar`'s resident dual-write reloads through
  `EmitLoadVar` and clobbers rax).
- `IRFirstEvaluated` — the mirror. Mirrors IR_BINOP's *guard chain*, not a
  guess: -O3 XMM fusion → unknown; the -O1 const-right / leaf-sym-right arms →
  LEFT first; the -O2 W1 mirror → unknown, because its `not InLValueWrite`
  guard is a RUNTIME flag this pass cannot see; every remaining arm → LEFT.
  Unknown is always safe: it costs a missed mark and nothing else.
- `IRMarkRedundantReloads` — runs last in the per-body pipeline, after
  IROptimize AND the residency passes, since those decide part of what the
  mirror has to agree with.
- `EmitReExtendRax` (symtab.inc, beside EmitLoadVar) — the consumer. Note the
  refinement over "skip the load": the store wrote only the low `TypeSize`
  bytes, so the reload's remaining job is the WIDTH fixup, and re-extending rax
  in place reproduces `EmitLoadVar`'s extension exactly without touching memory.
  That is what lets 1/2/4-byte slots participate instead of 8-byte ones only —
  `movsxd rax, eax` (3 bytes, no memory) in place of `mov rax, [rbp+off]`.

**Two comment pairs are marked MUST MOVE TOGETHER**: IRFirstEvaluated with
IREmitNode's IR_BINOP arm, and EmitReExtendRax with EmitLoadVar's scalar
else-branch.

**Measured, not assumed.** `PXXDBG=a.reload:*` prints every mark (node, sym,
name) — documented in `devdocs/dev/debug-switches.md`. The suite asserts the
FIRING COUNT as well as the values, because an -O0-vs-O3 differential that
passes because the pass never ran asserts nothing. Six marks fire in the test's
main body; the const-left and call-in-between cases are correctly not marked.

**Gate**

- `make compiler/pascal26` self-host fixedpoint + `tools/gate.sh quick` GREEN.
- `-O3` self-host fixedpoint: three-round self-compile converged byte-identical.
- The strongest oracle available here: an -O0-built and an -O3-built compiler
  emit BYTE-IDENTICAL output for the whole compiler source.
- `test/test_opt_store_reload.pas` — all four widths + pointer + Int64, the
  `y := 5 * x` negative case, and a call between store and use. Every value
  matches FPC 3.2.2 on the same source, and -O0/-O1/-O2/-O3 agree. Wired into
  `test-opt`, `test-core` and `test-nilpy`'s shared assertion block.

Stays at `-O3` (the free tier) per standing policy; promotion to `-O2` is a
separate call after the full gate has swept it.

## Unblocked

[[feature-opt-store-reload-elimination]] — its named reload is what this landed,
so that ticket is now about WIDENING the shape (more statement kinds than a
plain scalar store, and runs longer than two statements), not about the missing
scaffold.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
