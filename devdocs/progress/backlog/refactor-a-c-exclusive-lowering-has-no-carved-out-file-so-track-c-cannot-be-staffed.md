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

---

# INVENTORY — frankC, 2026-08-29. Reported before moving anything (grant condition 2). No line of `ir.inc` has been touched.

Measured at `3e76bb52a`. `compiler/ir.inc` is 13,570 lines and carries **40**
`CProgramMode` matches. **The count is wrong in both directions**, which is the
headline: it over-counts what is C by 18 and misses 232 lines that are.

## Classification of the 40

**One is not a site at all.** Line 1662 is *prose* — a comment recording that a
guard was **removed** (*"This arm was gated on `CProgramMode` for no reason the
guard itself needs"*, `feature-a-typeref-migrate-consumers`). 39 real guards.

| class | count | what it is | can it move to `cir.inc`? |
| --- | ---: | --- | --- |
| **A — C-exclusive** | **22** | lowering that only ever runs in C mode | yes, but see the shape problem |
| **B — Pascal/NilPy-only, C excluded** | **13** | `not CProgramMode` guarding *Pascal* code | **no — moving it would be backwards** |
| **C — shared two-armed dialect decision** | **4** | both dialects act, differently | **no — it is a shared rule** |
| — comment | 1 | records a guard already deleted | n/a |

### Class B — 13 sites that are not C lowering at all

`2864 7212 8282 8352 8966 8980 9343 9427 9448 9669 12752 12772 12830`

Every one is Pascal (or Pascal+NilPy) behaviour with C carved *out*: the
char-array/string conversions (`bug-p-a-char-array-is-not-a-string-in-any-direction`,
five sites), the PChar↔string wraps, the record-arithmetic and assignment-type
diagnostics, the cdecl-procvar reject, the enum/widechar write paths. The C
"behaviour" at each is **absence**. `IRCoerceCharArrayArg` (2864) is the clearest:
`if CProgramMode then Exit` as its first statement — a 50-line routine that is
*entirely Pascal's*.

**A naive "move the `CProgramMode` sites" would relocate a third of the Pascal
frontend into a C file.** This is the ticket's own warning (*"some are shared
lowering with a guard bolted on, which is a different defect"*) landing harder
than expected — the guard is not bolted onto shared lowering, it is bolted onto
*the other lane's* lowering.

### Class C — 4 shared decisions

| line | decision |
| --- | --- |
| 1758 | string-literal index base: `-8` (C, 0-based) vs `-7` (Pascal, 1-based) |
| 3801 | record argument: C always copies to a temp; Pascal branches on `isRefArg` |
| 10426 | literal→pointer store: `CProgramMode or IsNodePChar(dest)` — **one rule, two spellings** |
| 12074 | ternary arm type: `tyPointer` (C) vs `tyAnsiString` (Pascal) |

These are dialect *parameters*, not C code. 10426 is the interesting one: C says
"any pointer destination", Pascal says "a PChar destination", and they are the
same rule at different strictness — a `normalise-dont-special-case` candidate in
its own right, and **not** something to move.

### Class A — the 22 that are genuinely C, and why the obvious move fails

| shape | count | lines |
| --- | ---: | --- |
| whole routine is C-only | 1 | 2238 |
| C-only **tail** of a shared routine | 3 | 867, 2153, 2375 |
| C-only early-exit in a shared routine | 1 | 864 |
| **C arm inside a shared dispatch** | **17** | 1642 2406 2426 2440 2467 3152 3176 7165 7176 7309 7909 9288 10220 10461 10468 10529 10635 |

**Seventeen of the twenty-two are arms inside somebody else's `case` or
`if`-chain** — `IRLowerAST`'s giant AST-kind case, `IRLowerAddress` (604 lines),
`IRPointerStride` (182), `IRLowerCallArg` (1168). They cannot be lifted out
whole, because what surrounds them is the shared dispatch itself.

**This is the structural difference from the `parser.inc` precedent, and it is
why that precedent does not transfer unmodified.** Pascal parsing was *whole
procedures* — `ParseClassDecl`, `ParseGeneric` — so slicing them into
`pasparser_*.inc` was a file move. C lowering is *arms*, and an arm has no
boundary to cut along.

## What the 40-site grep MISSES — 232 lines, six whole routines

`CProgramMode` does not appear in them, so none is in the inventory. Each is
**reached only from a C-guarded call site**, verified by checking every caller:

| routine | line | size | reached from |
| --- | ---: | ---: | --- |
| `IRLowerBitFieldRead` | 959 | 70 | 7178, 10228 — both `CProgramMode` arms |
| `IRLowerBitFieldStore` | 1029 | 50 | 10227 — same arm |
| `IRLowerCompoundAssign` | 2169 | 41 | 9333, under `IRAssignIsSharedCompound` |
| `IRAddrMayCall` | 2075 | 28 | 2154 only, after `if not CProgramMode then Exit` |
| `IRAssignIsSharedCompound` | 2225 | 28 | 9331 |
| `CASTNodeOccursIn` | 2210 | 15 | only from `IRAssignIsSharedCompound` |
| | | **232** | |

`CASTNodeOccursIn` already carries the `C` prefix in its name — someone knew.
(`cparser.inc:12381` mentions `IRLowerBitFieldRead` in a comment only; it is not
a call, so nothing outside `ir.inc` reaches any of the six.)

**These six move with zero guard edits, zero behaviour change, and zero risk** —
they are whole routines with no non-C caller. They are the honest slice 1, and
the grep would never have found them.

## Proposed shape — extract bodies, keep the dispatch line

For the 17 arms, the move that works is **body extraction, not relocation**:

```pascal
{ ir.inc, at the arm }
if CProgramMode and (ASTKind[node] = AN_FIELD) and ... then
  Result := CIRLowerFieldArrayDecay(node, left)      { cir.inc }
```

`ir.inc` keeps a one-line guarded call per arm; `cir.inc` owns every body. That
is where the work and the future edits are — the guard line is stable, the body
is what `refactor-c-string-literal-decay` and
`refactor-c-the-partial-index-sentinel` actually need to change. **It does not
get Track C out of `ir.inc` entirely, and the ticket should stop promising
that**: adding a *new* C arm will always touch the dispatch. It gets C out of
`ir.inc` for the changes that are actually queued.

## Proposed slices

1. **The six invisible routines** (232 lines) into `cir.inc`. No guards touched,
   no behaviour change. Establishes the file and its include point.
2. **`IRPointerStride`'s four C arms + `IRNodePointerBase`'s tail** — the
   pointer/decay cluster, which is one coherent subject and is exactly what
   `refactor-c-the-partial-index-sentinel` needs to own.
3. **`IRDiscardValue` / `IRLowerDestAddress` tails** — the C
   assignment-as-expression cluster (864, 867, 2153) plus the load-backs
   (10461, 10468).
4. **The string-literal `+8` family** (9288, 10426, 10635, and the call-arg
   site) — this is `refactor-c-string-literal-decay-belongs-at-the-producer`'s
   whole subject; do that refactor *at the same time*, since the correct fix is
   to lower it once at the producer rather than move three copies.
5. Remaining arms, by dispatcher.

Classes B and C are **out of scope by measurement, not by preference** — 17 of
the 39 real guards stay in `ir.inc` permanently and that is correct.

## Two findings worth their own tickets — NOT filed by me, flagged for the owner

1. **The 13 Class-B sites are Pascal lowering carrying a C-shaped guard.** Several
   are the same `bug-p-a-char-array-is-not-a-string-in-any-direction` rule
   repeated at five sites (8282, 9343, 12752, 12830, and `IRCoerceCharArrayArg`),
   each with a comment pointing at the others. That is the `root-cause-over-microfix`
   "three copies is a design flaw" count, in Track P's ground, and it is a
   separate ticket from this one.
2. **`10426` is one rule spelled two ways** (`CProgramMode or IsNodePChar(dest)`).
   Normalising it would delete a Class-C entry rather than move it.

## Status

Inventory only. **`compiler/ir.inc` is unmodified and the tree is clean.** Awaiting
the go-ahead on the slice plan — specifically on whether slice 1 (the six
routines, 232 lines, no behaviour change) should land before the plan for the
arms is agreed, since it is independently safe and independently useful.

## Correction to the inventory, and to this ticket's main argument — frankC, 2026-08-29

### 1. The `parser.inc` precedent does not carry the weight this ticket puts on it

Stated plainly because it is this ticket's *principal argument*, it is quoted in
the prio raise above, and it is wrong:

**Pascal parsing was whole procedures, so slicing `parser.inc` into
`pasparser_*.inc` was a file move. C lowering is ARMS inside shared
dispatchers, and an arm has no boundary to cut along.** Seventeen of the
twenty-two C-exclusive sites are arms in `IRLowerAST`'s AST-kind case,
`IRLowerAddress` (604 lines), `IRPointerStride` (182) and `IRLowerCallArg`
(1168).

So the promise *"a `cir.inc` gets Track C out of `ir.inc`"* **cannot be
delivered**, and it should not be restated. Adding a *new* C arm will always
touch the shared dispatch. The deliverable goal is the narrower one: **get C out
of `ir.inc` for the changes that are queued** — which is achievable, and is what
the slices are for.

**Disposition on the arms (coordinator, 2026-08-29): extract per-arm, ON DEMAND,
driven by a queued ticket — never as a sweep.** The general question ("should all
seventeen read as a one-line stub plus a `cir.inc` body?") is deliberately left
open until two or three real extractions exist, so it can be decided from a diff
rather than a sketch — and so a bad answer costs three reverts, not seventeen.
A Track U ticket is deliberately NOT filed yet for the same reason.

### 2. Slice 1 is seven routines and 223 lines, not six and 232

Two corrections to my own numbers, both found while working out the dependency
order for the move:

**A seventh routine.** `CASTLValueHasSideEffect` (`ir.inc:2103`, 20 lines) is
called only from `IRAssignIsSharedCompound` and itself. Same shape as the other
six — C-prefixed name, no `CProgramMode` in its body, invisible to the grep.

**My 232 figure was measured wrong.** It used span-to-next-routine-start, which
for `IRLowerBitFieldStore` swept in the 24-line `PROMOTABLE INT lowering` comment
block belonging to the routine *after* it. Real body counts:

| routine | lines |
| --- | ---: |
| `IRLowerBitFieldRead` | 69 |
| `IRLowerBitFieldStore` | 26 (not 50) |
| `IRAddrMayCall` | 27 |
| `CASTLValueHasSideEffect` | 20 |
| `CASTNodeOccursIn` | 14 |
| `IRAssignIsSharedCompound` | 27 |
| `IRLowerCompoundAssign` | 40 |
| **total** | **223** |

### 3. "Pure relocation" acquires one forward declaration

The seven have a circular ordering constraint: `IRLowerDestAddress` (staying in
`ir.inc`) calls `IRAddrMayCall` (moving), and `IRLowerCompoundAssign` (moving)
calls `IRLowerDestAddress`. One include point cannot satisfy both, so `ir.inc`
gains one line:

```pascal
function IRAddrMayCall(n, depth: Integer): Boolean; forward;   { compiler/cir.inc }
```

Zero guard edits and zero behaviour change still hold. **Expect this shape in
every later slice** — the shared dispatchers and the C bodies call each other in
both directions, so each extraction is likely to leave a forward behind. That is
a real cost and the general-question decision should be made with it in view.

### 4. The method finding, which outlasts this ticket

**Not one of the seven contains the string `CProgramMode`.** The search that
defined the job could not see 223 lines of its own subject, while over-counting
by 18 in the other direction. Two of the seven carry a `C` prefix in their names
and the grep still missed them: **a name is not an index.**

The rule that found them, and the one to use for later slices: **follow CALLERS,
not the guard.** The guard says where the decision is made; it never says where
the work lives.

## SLICE 1 LANDED — frankC, 2026-08-30

Seven C-only routines out of `ir.inc` into the new `compiler/cir.inc`:
`IRLowerBitFieldRead` / `IRLowerBitFieldStore`, `IRAddrMayCall`,
`CASTLValueHasSideEffect`, `CASTNodeOccursIn`, `IRAssignIsSharedCompound`,
`IRLowerCompoundAssign`. `ir.inc` −230 / +10, `compiler.pas` +7.

### The gate — and why the usual one could not be it

**`make compiler/pascal26` is structurally blind to this entire slice.** Compiling
`compiler.pas` compiles *Pascal*; `CProgramMode` is never set; **not one of these
seven routines is ever called**. The fixedpoint would have gone green if their
bodies had been deleted. A gate that cannot fail is worse than no gate, because
it launders the change through everyone's trust in it.

**The `pasparser_*` precedent inverts here rather than transferring.**
`compiler.pas:126` says each of those slices is *"a contiguous range re-included
where it sat, which is what makes the carve-out provable by the self-host
fixedpoint"* — an argument that works *because Pascal parsing is what the
fixedpoint exercises*. A C carve-out is the exact case where it fails. That is
the second way this ticket's founding precedent does not carry.

**So the gate is a C-side equivalent, and it is the standing gate for this
refactor and every per-arm extraction** (adopted by the coordinator, 2026-08-30).
For a *relocation* claim, output equality is too weak — it would pass a semantic
change. Relocation must produce **identical machine code**. Ten C tests covering
all seven routines, sha256'd against the pre-move compiler `261e6cd2b58f`,
rebuilt after:

```
canon_bitfield_b310 66f59407f54c   cbitfield_arith_precision 78c5eaf6b5f2
cbitfield_longlong_b359 62709c2fc25d   cbitfield_mixed_type_pack_b373 4d4e710c39d1
cbitfield_promotion_b358 201cf0c82b2c   csigned_bitfield_b306 490e0650460f
cassign_compound_lvalue_once bc0bb454c366   cassign_dest_call_once e873b0aa848c
cassign_value_b43 849b560a76ba   cstruct_assign_dest_side_effects ec89940cc167
```

**All ten byte-identical, outputs identical.** Plus `forwardlint` clean, and
`gate.sh quick` GREEN — including its `fpc seed compiles (forward decls)` step,
which is what actually exercises the five new forwards.

### Forward count: 5, not the 1 predicted

**The include position I proposed did not exist.** I assumed `{$include cir.inc}`
could sit *inside* `ir.inc`'s stream after `IRLowerDestAddress`, costing one
forward. The flat convention puts it in `compiler.pas`, which can only place
`cir.inc` before or after the **whole** of `ir.inc`. Both options were measured:

| position | forwards | where they live |
| --- | ---: | --- |
| `cir.inc` **after** `ir.inc` | **5** | in `ir.inc`, for what it calls forward |
| `cir.inc` before `ir.inc` | 6 | in `cir.inc`, for what it borrows |

*After* was chosen not on the count but because **before is not viable**:
`cir.inc` calls `IRLowerAST`, which `ir.inc` already forward-declares at 675, so
placing `cir.inc` first needs a second forward for it — a duplicate the FPC seed
rejects, and precisely what `forwardlint` exists to catch.

**Carry the 5 into the arms decision, not the 1.** And expect worse there: an
arm's body reaches back into the locals of the dispatcher it was cut from, which
relocating a whole routine never does.

### Cross-finding, same evening, other direction (frankA, `2d57b9744`)

`ParsingClassBodyCi`'s `-1` sentinel was initialised **only inside
`ParseProgram`**, the Pascal entry point, so every other frontend ran with the
BSS default `0` — a valid `UCls` index (`TGuid`). **ALGOL, Erlang, Rust, Zig, C
and asm all carried the hole; only NilPy had the users to expose it.**

Same root property as the blind gate, with the roles reversed: **the shared gate
exercises the Pascal path, so anything true only off that path is unobserved by
construction** — in the gate's blindness and in the bug's survival alike. Two
independent findings in one evening arguing for the same remedy, which is why
the C-side byte-identical gate is not a local nicety for this refactor.

## Grant, 2026-08-30 — frank-coordinator to frankC: IRPointerStride's AN_FIELD arm

Extends the standing `ir.inc` grant by ONE routine. `IRPointerStride` lives in
`compiler/ir.inc` (Track A's ground); `CNodePointeeTk`, `CDerefDecayStride` and
`ParseCPostfixTail` are already frankC's in `cparser.inc`.

**Granted:** separate commit, own ticket, alongside the sentinel refactor.

**Why it is safe rather than merely small.** Checked, not assumed —
`tools/fleet_dirt.sh` across all 16 discovered checkouts at the time of the
grant: `compiler/ir.inc` is held by **frankC alone**. frankA is in
`pasparser_lval/_expr/_stmt`, frank-rust in `pasparser_generic.inc`, frankS in
`ir_codegen_xtensa.inc`, pxx-songfmt in `pyparser.inc`. No second lane is in the
file, so the no-concurrent-edit rule the letters exist to enforce is not in play.

**Why it is not scope creep.** The bug is *inside the arm frankC is already
re-keying*, is not long-long-specific, and produces silent wrong ADDRESSES:

| expression | type | gcc | pxx |
| --- | --- | --- | --- |
| `(char*)(s.m+1)-(char*)s.m` | `int m[3][4]` | 16 | 4 |
| same | `char c[2][8]` | 8 | 1 |
| same | `double d[2][3]` | 24 | 8 |
| `int (*r)[4] = s.m + 1; r[0][2]` | | 7 | 0 |

A multi-dim array reached as a struct FIELD decays with the ELEMENT stride. The
`AN_IDENT` arm directly above it has the multi-dim row rule; the `AN_FIELD` arm
never got it. Under the compat table in CLAUDE.md this is the *silent wrong
behavior* escape — a normal `bug-` ticket in the owning lane, not a compat item.

**The condition, and it is the whole point:** frankC declined to trim the failing
assertion out of its long-long regression test to make the suite pass. That is
the correct call and it is what forced the ask instead of a quiet workaround. The
grant exists so the complete test can land with the fix rather than the test
being cut to fit the permission.

## The pattern the grant is really about — parallel AN_IDENT / AN_FIELD arms

**Third field-arm bug in one day whose array-arm twin was fixed months ago.**
`ParseCPostfixTail` and `IRPointerStride` each carry parallel `AN_IDENT` and
`AN_FIELD` arms, and *every past fix landed on one of the two*. Two more readers
walk left to an `AN_IDENT` and ignore `AN_FIELD` and are so far unprobed:
`CNodePointeeTk`'s `AN_BINOP` arm, and `CDerefDecayStride`.

This is `normalise-dont-special-case` and *a parser that exists twice is one that
gets fixed on one arm*, with three landed instances as evidence rather than as a
prediction. **Sweep scoped as its own ticket** — meeting it a fourth time costs
more than enumerating the readers once. Note what makes it expensive: the two
arms are adjacent in the same routine, so each fix *looks* local and complete,
and nothing in a diff shows the sibling going unedited.

`AN_FIELD` reader census to start from (not a completeness claim — the count is
per-file mentions, and the C-side readers are what matters):
`ir.inc` 44, `cparser.inc` 17.
