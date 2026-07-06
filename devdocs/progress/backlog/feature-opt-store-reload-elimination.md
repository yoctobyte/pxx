---
prio: 60  # auto
---

# Store-reload (redundant load) elimination — -O1 pass

- **Type:** feature (codegen — optimization pass) — Track A
- **Status:** backlog — **BLOCKED on a register-liveness scaffold**
- **Opened:** 2026-07-03 (pin-time optimization campaign)
- **Umbrella:** a candidate -O1 pass under [[feature-optimization-levels]]
  (listed there as low-hanging item 2, "redundant load elimination"); split
  out because — unlike the landed pass 1/2/3 peepholes — it needs
  cross-statement register-value tracking, not a local one-node rewrite.

## What it does

The single-pass emitter round-trips memory at every assign-then-use seam:

```pascal
x := a + b;    { mov [rbp+xoff], rax   ; store result to x's slot   }
y := x * 2;    { mov rax,  [rbp+xoff]  ; RELOAD x for the next use   }
```

After the store, `rax` STILL holds x's value — the reload reads the same value
back from memory for nothing. Elimination drops the reload and keeps using the
register. Real speed win: the pattern is pervasive (every `v := expr;` followed
by a statement that uses `v` first), hot in loops and expression chains. Two
memory ops removed per hit. Sibling of item 6 in the umbrella ("dead store to
hidden temps" — a lowering-time temp written once and read once immediately
after can bypass its frame slot entirely; same liveness need).

## Why it is blocked (the hard part)

Investigated 2026-07-03 while landing passes 2/3. Two ways to catch it, both
currently unavailable:

1. **Byte-level lookback** — inspect the just-emitted `Code[]` bytes, see
   `mov [slot],rax` immediately followed by an about-to-emit `mov rax,[slot]`,
   suppress the reload. **Forbidden here:** branch/label fixups store ABSOLUTE
   `CodeLen` offsets, so we never reason over or shift emitted bytes
   (`Patch32`/`LabelFixupPos` all reference fixed positions). This is the
   standing rule from the -O plumbing work.

2. **IR-level value tracking (the correct way)** — maintain "register rax
   currently holds the value of symbol S", and when an `IR_LOAD_SYM(S)` is
   reached while that fact holds, skip the load. **Structurally blocked:** the
   redundant reload does NOT sit adjacent to the store in the IR stream — the
   IR is a flat post-order array where `IR_BLOCK(first,last)` is a no-op range
   marker and a driver loop (`for i := 0 to IRCount-1`) emits statement roots
   while recursing `IREmitNode` for operands. The reload lives DEEP in the
   *next* statement's expression tree (e.g. the left leaf of its top BINOP),
   so no cheap stream peephole over statement roots sees it. A correctness-safe
   tracker must be INVALIDATED the instant anything writes rax — but on x86-64
   rax is written by hundreds of scattered raw `EmitB($48);EmitB($B8);...`
   sites across `ir_codegen.inc` with NO single choke point to hook. Miss one
   invalidation → the tracker believes rax holds a stale value → SILENT
   MISCOMPILE that passes many tests and ships a wrong answer. Correctness >
   speed: not landing a half-safe tracker.

The concrete failure that killed the naive attempt: with
`y := 5 * x` (const LEFT operand), the driver evaluates the left leaf
`MovRaxImm(5)` — which clobbers rax — BEFORE reaching `IR_LOAD_SYM(x)`. A
tracker that only knows "rax held x after the store" would wrongly skip the
x load and use 5. Correct invalidation therefore has to intercept EVERY
rax-writing emission, which the current raw-`EmitB` codegen cannot offer
cheaply.

## Unblock path

Build (or reuse) a **register-liveness / value-tracking scaffold** — the same
one [[feature-callconv-register-args]] needs (passing args in registers also
requires knowing what each register currently holds and when it dies). Options:

- Route ALL accumulator writes through a small set of primitives
  (`MovRaxImm` is already one; `EmitLoadVar`, the arithmetic emitters, calls,
  etc. are not) so there is a single invalidation choke point, then a
  conservative "last value in rax = sym S, cleared on any rax write / call /
  label / store to S" cache becomes airtight.
- Or a proper per-basic-block liveness/value-numbering pass over the IR before
  codegen (blocks delimited by `IR_LABEL`/`IR_JUMP*`), emitting a "this
  `IR_LOAD_SYM` is redundant, its value is already live in rax" annotation the
  emitter honours.

Either way it is shared infrastructure with the -O2 regcall work — do them
together, or land the scaffold first as its own ticket.

## Gates (when it lands)

- `-O0` self-host byte-identity UNTOUCHED (pass gates on `OptLevel >= 1`).
- `make test-opt` differential corpus green (same program -O0 vs -O1 = identical
  runtime output) — the cheap oracle that catches exactly this class of
  miscompile.
- Full `make test` under an -O1-BUILT compiler; -O1 self-host fixedpoint
  byte-identical.
- Measured cycle win recorded in [[feature-optimization-levels]] log.

## Related

- [[feature-optimization-levels]] — umbrella; passes 1-3 already landed
  (leaf-const operand load, leaf-sym operand load, const-load size peephole).
- [[feature-callconv-register-args]] — shares the register-liveness scaffold
  that unblocks this.
