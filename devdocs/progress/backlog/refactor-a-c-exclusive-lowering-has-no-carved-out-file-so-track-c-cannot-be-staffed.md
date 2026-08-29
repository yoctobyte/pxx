---
track: A
prio: 60
type: refactor
status: backlog
blocked-by: []
owner: ""
summary: "C owns its lexer/parser/preproc but NOT its lowering: ir.inc carries 40 CProgramMode references. So most Track C work needs Track A's files, and a C agent cannot be staffed independently -- measured 2026-08-29, four of six ranked C tickets need an A file."
---

# C-exclusive lowering has no carved-out file, so Track C cannot be staffed independently

- **Type:** refactor (structural / coordination) — **Track A** (owns `ir.inc`).
- **Found:** 2026-08-29 by frankC, working down the Track C queue; measured and
  confirmed by the coordinator.

## The measurement

Track C owns `clexer.inc`, `cparser.inc`, `cpreproc.inc` and `lib/crtl`. It does
**not** own a lowering file — there is no `cir.inc`. C-exclusive lowering lives
in the shared `compiler/ir.inc`, which carries **40** `CProgramMode` references.

The consequence, over the six ranked Track C tickets:

| ticket | file it must edit | workable by a C-only agent? |
| --- | --- | --- |
| `refactor-c-string-literal-decay-belongs-at-the-producer` [p50] | `ir.inc` | **no — A** |
| `feature-c-diagnostics-name-the-module-they-are-in` [p40] | `lexer.inc` | **no — A** |
| `refactor-c-the-partial-index-sentinel` [p40] | `cparser.inc` + `ir.inc` | **no — C+A** |
| `feature-c-import-a-pascal-unit-under-a-mangled-name` [p50] | — | no — blocked on the user |
| `idea-c-realworld-test-targets` [p60] | — | no — brainstorm parent |
| `compat-c-printf-p-of-null` [p22] | `lib/crtl` | yes — **resolved `e885d94ef`** |

**`ready --track C` prints nine items; exactly one was workable, and it is now
done.** That gap is why "Track C has a queue and no agent" read as an easy
staffing win on 2026-08-29 and was not one.

## Why this is a real defect and not just how it is

The tracks are **file-lanes for collision avoidance**. A lane whose work
predominantly lands in another lane's files is not a lane — it is a label, and
it silently converts every C dispatch into a request for the A slot. Compare:

- **P** had exactly this problem and it was fixed. The 37,249-line `parser.inc`
  was sliced into `pasparser_*.inc` on 2026-08-20 precisely so Pascal frontend
  work would stop needing A's slot. (Its lexer is still shared — the known
  residual.)
- **R** and **Z** own `rparser.inc` / `zparser.inc`.
- **N** owns `pylexer.inc` / `pyparser.inc` and is explicitly called out in
  CLAUDE.md as the low-risk combination *because* it is carved out.

C is the frontend that got its parser carved out and its lowering left behind.

## It is a half-finished migration, not a design choice

frankC's framing, added 2026-08-29 and sharper than the original: **C is the only
mainline frontend whose parser was carved out and whose lowering was not.** That
makes the asymmetry a migration nobody finished rather than a deliberate split —
which is what turns this into a refactor with a **known-good precedent** (the
`pasparser_*` split of 2026-08-20) instead of an open design question. Nobody has
to decide whether C *should* own its lowering; every other frontend already does.

It also predicts the payoff, which the table above does not. A `cir.inc` would move
`refactor-c-string-literal-decay`, `refactor-c-the-partial-index-sentinel` and
probably `feature-c-diagnostics-name-the-module` from "needs the A slot" to
"ordinary C work" — **three of the four tickets that made the lane unstaffable.**
The value is not tidiness; it is that Track C becomes dispatchable in parallel with
Track A, which it is not today.

## What to do

Carve C-exclusive lowering out of `ir.inc` into `cir.inc`, the way
`pasparser_*.inc` was carved out of `parser.inc`. The 40 `CProgramMode` sites
are the starting inventory, not the definition — some will be genuine shared
decisions that must stay.

**Do not treat the count as the scope.** The `parser.inc` split's lesson was
that the machinery which was never Pascal went to its real owner (`ast_arena`,
`inline_expand`, `ast_syminfer` to A; NilPy's forwards to N). Expect the same
here: some of the 40 are C-shaped things that belong to C, and some are shared
lowering with a `CProgramMode` guard bolted on, which is a different defect.

## Until then

Track C is **one agent's worth of work at a time, gated on the A slot**, not an
independently staffable lane. A coordinator staffing C should either pair it
with the A slot or expect it to run dry. That is the operational fact this
ticket exists to remove.

## Prio raised 45 -> 60 by the coordinator, 2026-08-29 — and why it had to be by hand

**This is a coordinator call, not the owner's.** Recorded here rather than left
implicit so it can be vetoed in one edit.

The board's ranking model is *"one human `prio:` propagated down dependency
edges — a blocker inherits the priority of what it unblocks, so you rate goals
and the chain follows."* That mechanism **cannot fire on this ticket**, and the
reason is measurable:

```
$ grep -rl "c-exclusive-lowering" devdocs/progress/{urgent,backlog,backlog_new,unfinished,blocked}/
$          # zero files
```

**No ticket declares this one as a blocker**, so it has no in-edges and inherits
nothing. It sat at 45 while ranked *below* five tickets it is the blocker for —
frankC's words, 2026-08-29: *"that p45 is the ticket that unblocks my lane, and
it is ranked below four things it is blocking."*

**The edges were not simply forgotten — adding them would be a false claim.**
`blocked-by:` means *cannot proceed*, and those five C tickets can proceed
perfectly well: by an agent holding the A slot. Marking them blocked would hide
real Track A work from Track A's queue in order to fix a ranking artefact. So
the honest repair is the `prio:` field, which is what it is for.

**Generalisable, and worth more than this ticket:** *prio propagation is only as
good as the edges someone drew, and a structural blocker is exactly the kind
that never gets an edge* — because it blocks a **lane**, not a ticket. Nothing
in the tooling can see that. A ticket whose beneficiaries are "most of track X"
will always under-rank itself, and no checker will flag it, because from the
ranker's side an in-degree of zero is indistinguishable from a leaf.

### Instance five, which is what moved the number

frankC predicted this ticket's own consequence and then hit it, on
`refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag` [C p40] — a
ticket the coordinator picked **specifically because it looked disjoint**:

```
ParseCPostfixTail    compiler/cparser.inc:3696   Track C
CNodePointeeTk       compiler/cparser.inc:2051   Track C
IRNodePointerBase    compiler/ir.inc:2348        Track A   <-- the 12 lines that ARE the refactor
IRPointerStride      compiler/ir.inc:2390        Track A
```

Neither sketched option escapes `ir.inc`: the `ASTSLen`-style stamp is read by
`IRPointerStride`'s AN_BINOP arm, and the dedicated-AST-node option is *worse*
for C, since a new AST node is a Track A ticket C files rather than code C
writes. Landing only the `cparser` half would write the sentinel **twice** —
tag and stamp, with A's reader still on the tag — which is strictly worse than
today. The ticket's own gate line (*"the `tyInt64` special case in
`IRNodePointerBase` is gone rather than moved"*) requires the A file by
construction.

The table above therefore reads **five of seven ranked C tickets need an A
file**, not four of six. It has gone up, not down, since the ticket was filed
this morning — and it went up on the very ticket chosen to test whether the lane
had disjoint work in it.

**The disposition matches the precedent already set on
`refactor-c-string-literal-decay-belongs-at-the-producer` [C p50]:** keep
`track: C` for visibility, note in the body that the edit needs the A slot.
*"File-lanes exist for collision avoidance, not as a taxonomy, so the rule is
about the FILE and not the topic."* That ruling should not need re-deriving a
sixth time, which is itself an argument for this refactor rather than for
another routing note.

## GRANT — `compiler/ir.inc` to frankC (Track C) for this carve-out, 2026-08-29

**Granted by the coordinator.** Filed rather than left in message traffic: an
authorisation is a finding about what is permitted, and an unfiled grant reads
as *covered* rather than as missing.

**Why the holder is a C agent and not an A agent.** This is Track A work by file
and Track C work by motive. frankC diagnosed the need, produced the five-of-seven
measurement, and hit instance five itself; it is also the only session that will
know immediately whether a given `CProgramMode` site is genuinely C-exclusive or
shared lowering with a guard bolted on — which is the distinction the whole
refactor turns on, and the one an A agent would have to rediscover.

**Precondition verified at grant time, not assumed.** `compiler/ir.inc` is clean
in **all twelve clones**. Adjacent-but-disjoint holders: frankA
(`pasparser_decl.inc`, `symtab.inc`), frankS (`ir_codegen_xtensa.inc`, plus the
granted `defs.inc` line), frank-optimize-b4 (`ir_codegen.inc`), frank-rust
(`pasparser_generic.inc`), the T tree (`pasparser_proc.inc`). **`ir.inc` itself
is held by nobody**, and the coordinator holds the slot for frankC until frankC
releases it.

**Conditions, and the second one is the load-bearing one:**

1. **`compiler/ir.inc` and the new `compiler/cir.inc` only.** Anything else —
   `symtab.inc`, `defs.inc`, a new AST node or IR op — is a separate ask.
2. **Report the inventory BEFORE moving anything.** The 40 `CProgramMode` sites
   are the starting inventory, **not the scope**. The `parser.inc` split's actual
   lesson was that machinery which was never Pascal went to its *real* owner
   (`ast_arena`, `inline_expand`, `ast_syminfer` to A; NilPy's forwards to N),
   and the same is expected here: some sites are C-shaped and belong to C, and
   some are **shared lowering with a `CProgramMode` guard bolted on, which is a
   different defect** and must not be moved as if it were the first kind.
   Classifying them is the deliverable that survives even if the move stalls.
3. **Land in committed slices, not one move.** Slices 1-6 of the speculative-parse
   work are the model. A single large `ir.inc` rewrite is unmergeable against five
   live lanes; a sequence of small ones is not.
4. **Gate is A's:** `make compiler/pascal26` to fixedpoint per slice, `gate.sh
   quick` before any pin. Land only green.
5. Tell the coordinator before touching `ir.inc` for anything outside this
   refactor, and on release.

**Expiry:** when this ticket resolves, or when frankC reports the slot released —
whichever is first. A later `ir.inc` change is a later ask.
