---
track: A
prio: 60
type: feature
blocked-by: []
owner: agent-A
---

# Store-reload (redundant load) elimination — -O1 pass

- **Type:** feature (codegen — optimization pass) — Track A
- **Status:** done
  now a ticket rather than a paragraph (see the 2026-08-03 note at the end)
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


## 2026-08-03 — the blocker is now a TICKET, and it is still real

This sat in `backlog/` with the blocker described in prose but no `blocked-by:`
field, so `progress.sh ready` offered it as pullable work for a month. It is
not: the naive version ships a silent miscompile.

Re-checked rather than inherited, because [[feature-callconv-register-args]] has
landed since and its write-up mentions liveness. What that ticket actually built
is MEASUREMENT — `InlineMeasureBody` / `RegcallMeasureBody` counting
makes-a-call, early-exit and addr-taken-param over the IR. No value tracking,
no choke point for accumulator writes. **The blocker is unchanged.**

Split out as [[feature-opt-accumulator-value-tracker]] so it can be ranked, and
because it unblocks more than this pass (the "dead store to hidden temps" item
on the umbrella needs the same fact). `blocked-by:` added above.

## Triage 2026-08-19 (Track D re-triage pass) — UNBLOCKED: the blocker is done

`feature-opt-accumulator-value-tracker` — the scaffold this was waiting on — is
in `done/`, with a summary that names this exact dependency: *"the
register-value scaffold two -O passes are blocked on"*. So the `blocked-by`
edge was satisfied and the ticket was sitting in `blocked/` anyway, invisible
to `ready`, at prio 60 — the highest-ranked A feature in the queue.

`blocked-by` cleared and the ticket moved to `backlog/`. Nothing about the pass
itself is stale; re-read the 2026-08-03 note at the end against what the
tracker actually shipped before starting, since the split was written before
the scaffold existed.

## Resolved 2026-08-21 (agent-A) — the WIDENING, measured

The scaffold ticket [[feature-opt-accumulator-value-tracker]] landed the reload
elimination itself; what was left here, in its own words, was *"WIDENING the
shape (more statement kinds than a plain scalar store, and runs longer than two
statements)"*.

**Runs longer than two statements already worked.** The pass loops over every
`i`, so `x := …; y := x…; z := y…` is examined as two independent adjacent
pairs and both marks land. Nothing to do there — worth recording, because the
ticket's phrasing suggests otherwise.

**The statement kinds were the whole gap, and the numbers said which one.**
Rather than guess, the rejection reason was counted over a full self-compile
(temporary `PXXDBG=a.why` probe, since removed) — for every store that was
itself eligible, what stopped the NEXT statement from being usable:

| next statement | count |
| --- | ---: |
| `IR_JUMP_IF_FALSE` | **18,840** |
| `IR_LABEL` | 15,916 |
| `IR_JUMP` | 6,200 |
| first-evaluated unknown | 3,210 |
| `IR_STORE_MEM` | **3,156** |
| destination not elim-safe | 2,120 |
| `IR_CALL` | 1,961 |
| a different symbol | 1,920 |
| first-evaluated is a const (the negative case) | 1,722 |
| `IR_TERMINATE` | 1,552 |

`IR_LABEL` and `IR_JUMP` are correct refusals — a label ends the basic block
and a jump has no value expression. `IR_CALL` and `IR_TERMINATE` were left
alone: their arms emit before reaching an argument. The two that reach their
value expression with **nothing emitted before it** are the branch and the
address-store, and those are what this change adds.

### `IRStmtFirstEvaluated` — a second mirror, at statement level

`IRFirstEvaluated` answers "what does this value TREE emit first". The new
function answers it for a STATEMENT, which is a genuinely different dispatch:

- **`IR_STORE_SYM`** — what the pass already did (kept behind the same
  `ReloadElimSym` destination test, because a record/set/managed destination
  emits an address or a release-of-old before the value is reached).
- **`IR_STORE_MEM`** — `p^ := …`, `a[i] := …`, `r.f := …`. The generic arm
  evaluates the VALUE first and computes the destination address after it.
  The tyString / tyAnsiString arms are excluded: both run retain/release
  machinery of their own.
- **`IR_JUMP_IF_FALSE`** — and this is the one that needed care. The fused
  compare-into-branch has its **own** operand-order chain, parallel to
  `IR_BINOP`'s but not the same one: no imm-fold arm, and both -O3 scratch arms
  evaluate LEFT first. Only the -O2 W1 mirror reorders to right-first, and its
  `not InLValueWrite` guard is the same runtime flag `IRFirstEvaluated` cannot
  see — so it answers unknown for exactly the same reason. Mirroring
  `IR_BINOP`'s chain here instead of the fusion's would have been wrong in both
  directions.

Both mirrored emitter arms now carry a **MUST MOVE TOGETHER** comment pointing
back, matching the two pairs the scaffold ticket already marked.

### Effect

- Marks over a full self-compile: **1,651 → 17,700** (10.7x). The branch kind
  is 16,000 of that; `IR_STORE_MEM` adds 162.
- Emitted code at `-O3`, same source, narrow-pass compiler vs widened-pass
  compiler: **-0.78%** on the compiler (8,894,190 → 8,824,585 B) and -0.75% /
  -0.83% / -0.81% on satdemo / sieve / chess. Consistent, so it is the pass and
  not one program's shape.
- **Runtime: no change measurable above noise.** chess best-of-5 0.95s narrow
  vs 0.97s wide; a self-compile 25.82s vs 25.58s best-of-3 with medians 25.83
  vs 25.88. The box also runs Track T, so this is a weak measurement — but the
  honest report is "smaller code, no demonstrated speedup", not a number
  rounded in the flattering direction. Store-to-load forwarding is exactly what
  an out-of-order core hides best.

### Gate

- `make compiler/pascal26` self-host fixedpoint (default -O) byte-identical,
  `tools/gate.sh quick` GREEN.
- **-O0-built and -O3-built compilers emit byte-identical output** for the whole
  compiler source — the strongest oracle available for this class of bug.
- **-O3 self-host fixedpoint**: an -O3-built compiler compiles itself twice to
  byte-identical binaries.
- `-O0`/`-O1`/`-O2`/`-O3` agree on `test/test_opt_store_reload.pas`, and every
  value matches FPC 3.2.2 on the same source.
- Eight further programs compiled at -O0 and -O3 produce identical output.

### The test

`test/test_opt_store_reload.pas` gained twelve lines of new shape, each a WIDTH
oracle rather than only a control-flow one — the truncated store and the
untruncated rax straddle the comparison threshold, so a missing re-extension
flips the branch and prints the other word:

- `c := ShortInt(200)` (= -56, rax holds 200) then `if c < 0` — fused compare.
- `w := Word(70000)` (= 4464, rax holds 70000) then `if w > 60000`.
- `u := LongWord(2^32+5)` (= 5, rax holds 2^32+5) then `if u > 100`.
- a Boolean condition — the NON-fused arm.
- `if 5 > i` — the const-left negative case in branch position, which must
  still reload.
- a `WriteLn` between the store and the branch — the run must end there.
- `arr[0] := c*2`, `rec.f := c*2`, `pi^ := c*2` — the three `IR_STORE_MEM`
  destinations.

The Makefile rows assert the firing count AND that each widened kind fired
(`bo` is only ever reloaded by a non-fused branch; `c` by the fused compare plus
the three address-stores). On the pinned pre-change binary those two counts are
0 and 1 — so the assertions genuinely guard the widening, not just the values,
which are identical before and after by construction.

### Left on the table

`IR_CALL` (1,961 sites) and `IR_TERMINATE` (1,552) — both emit before reaching
an argument, so they need more than a mirror. `IR_LABEL` (15,916) is not
reachable at all without cross-block reasoning, which is a different pass.
Still `-O3` only, per the standing "new passes land on the free tier" policy.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
