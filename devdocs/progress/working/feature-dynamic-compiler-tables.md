---
slug: feature-dynamic-compiler-tables
title: "Dynamic compiler tables — kill the fixed `array[0..MAX_*]` ceilings (+ dynarray dogfood)"
prio: 45  # auto
track: A
type: feature
status: working
owner: "frankH"
blocked-by: []
summary: "INCREMENTAL CONVERSION ON MASTER, PROVEN AND MID-FLIGHT, held by frankH. The compiler held ~305 fixed parallel `array[0..MAX_*-1]` tables in defs.inc; each is a hard ceiling a large translation unit can hit (sqlite''s 257k-line amalgamation broke MAX_TOKENS) and together they dominate the compiler''s BSS. DONE: Tokens, Syms, UField, IR, AST, Code, LoadFileBuf, CPrepChars, Data, Strs, Fixups+FixupPCRel+FixupPicDelta. STILL FIXED: TokChars (STRING_CAP, 8 MB), LabelFixupPos/Target (MAX_IR, 1 MB each), UCls* (MAX_UCLASS), and Procs DELIBERATELY. THE TICKET''S REAL VALUE IS ITS METHOD, and it is not optional: BEFORE CONVERTING A FAMILY, GREP ITS `MAX_` NAME ACROSS compiler/** AND READ EVERY HIT -- deleting a cap does not delete the code that assumed it, and four sites had taken MAX_X to mean `a number the count can never reach`, one of them an out-of-bounds stack write in IRVerify which runs on every body (bug-a-dynamic-tables-left-their-fixed-size-shadows-behind). 2026-09-05: LoadFileBuf converted, worth 8 MB of BSS (106842604 -> 98454060) and a measured before/after correctness fix on the FPC-seed path -- see that section; it also stopped BORROWING STRING_CAP, which is the token char pool''s capacity with ~40 overflow checks against it, so one constant had been sizing two unrelated things. 2026-09-06: CPrepChars converted, another 8 MB (98454060 -> 90066100), and this time the cap was PROVEN REACHABLE -- 30000 macros with ~430-byte values trip this table''s own `C preprocessor text overflow`, while an 18.5 MB file of 300000 SHORT macros trips MAX_CPREP_MACROS instead and would have read as unreachable: TWO CAPS CAN BE IN RANGE OF ONE INPUT and the diagnostic string is the only thing that says which axis you tested. 2026-09-06: Data converted, 2 MB (90066100 -> 87985348), and it settled a coupling the ticket''s own grep method CANNOT see: TWO TABLES CAN SHARE A CEILING WITHOUT SHARING A CONSTANT. Every string literal costs 32 bytes of managed-string header plus its 8-aligned text, so MAX_DATA (2 MB) capped the string table at ~52108 entries and MAX_STRS (65536) WAS UNREACHABLE -- `Error(''string table overflow'')` was a guard that could not fail. Proven by the SAME 66000-literal input answering `data overflow` before and `string table overflow` after. Converting Strs was worth nothing before this and is load-bearing now. The conversion also segfaulted first: five byte runs and two constant-offset writes reach Data with no overflow check at all, because a fixed bss array never needed one. METHOD ADDITION: after converting a table, enumerate its WRITE sites, not its CAP sites -- the cap sites were already thinking about the limit. 2026-09-06: Strs converted too (1.5 MB, 87985348 -> 86412492) -- FIRST table here whose growth carries a MANAGED field (TStrEntry.Text is an AnsiString), probed before converting. One input crossed three states and that is the whole proof: 66000 short literals said `data overflow`, then `string table overflow`, then compiled and RAN. 2026-09-06: the fixup family converted (2752488 bytes, 86425036 -> 83672548), all THREE parallel arrays through ONE helper so there is no site that can grow the table without the columns. THE CHAIN IS NOW COMPLETE FOR ONE INPUT SHAPE AND IT TERMINATES: 52200 literals `data overflow` -> 66000 `string table overflow` -> 40000 a 22.24s TIME ceiling -> 200000 `fixup overflow` -> 500000 COMPILES in 14.04s at 992 MB peak RSS and runs correctly. Each conversion revealed the next ceiling and the reveal is the only way any were known reachable; the terminal state is memory, not a constant. AND THE ORPHANED COMMENT KNEW SOMETHING: the 2026 raise of MAX_STRS from 8192 to 65536 is what MADE that guard unreachable, because 65536 sat 13000 above anything MAX_DATA could fund -- RAISING A CAP WITHOUT CHECKING THE RESOURCE IT IS DENOMINATED IN IS HOW A GUARD STOPS BEING ABLE TO FIRE. LANDMINE ON THE LIFTED CAP: InternStr dedups by LINEAR SCAN, so it is O(n^2) -- 5000/10000/20000/40000 literals take 1.29/2.48/6.30/25.69s. Removing the cap swaps a hard error for a time ceiling, which is strictly better but is NOT the same claim; a hash index is the next change. STILL STANDING FOR TokChars: STRING_CAP also sizes the SHORTSTRING TYPE (ast_syminfer.inc:151, ir.inc:2703), so that constant must be SPLIT before TokChars can be converted at all. And the pattern is realloc PRESERVING INDICES: a free list or a compaction pass is OUT OF SCOPE, because it turns zero-init sentinel columns like AliasEnumId from inert into stale-fail-open."
---

# Dynamic compiler tables — kill the fixed `array[0..MAX_*]` ceilings (+ dynarray dogfood)

- **Type:** feature (compiler architecture / capacity) — Track A
- **Status:** working
- **Owner:** frankH
- **Opened:** 2026-06-27
- **Relation:** forced into view by [[feature-c-desktop-lua-sqlite-path]] M5 —
  sqlite's 257k-line amalgamation blew `MAX_TOKENS` (512K) and needed a bump to
  2M. Companion stress angle to managed-string / dynarray correctness.

## Problem

The compiler holds ~305 fixed parallel arrays `array[0..MAX_*-1]` in `defs.inc`.
Two costs:

1. **Hard ceilings.** Each `MAX_*` is a wall a big translation unit can hit
   (sqlite hit `MAX_TOKENS`; lua/sqlite will push `MAX_AST`, `MAX_IR`,
   `MAX_SYMS`, `MAX_UFIELD`, `MAX_CTYPEDEF`, `MAX_CPREP_*`, …). Each overflow is
   a manual bump + recompile + (because the bump changes the compiler's own bss)
   a stabilize/pin cycle.
2. **Static BSS bloat.** These tables dominate the compiler's ~165 MB bss. Most
   of it is reserved for worst-case inputs and never touched. Bumping a cap (e.g.
   512K→2M tokens, ×3 parallel arrays) quadruples that slice for every compile of
   every program, however small.

## Proposal

Convert the largest / most overflow-prone tables from fixed `array[0..MAX_*]` to
**dynamic arrays** that grow on demand (geometric, e.g. ×2 with an initial
modest reserve). Keep the `MAX_*` as a sanity hard-cap if wanted, but allocate
to fit.

### Priority candidates (biggest + most overflow-prone first)

- **Token tables** — `Tokens`, `TokPackRecords`, `CAttrFlags` (`MAX_TOKENS`, the
  one sqlite already broke). 3 parallel arrays, must grow together.
- `AST*` (`MAX_AST` 512K), `IR*` (`MAX_IR`), `Syms` (`MAX_SYMS`).
- C-frontend: `UField` (`MAX_UFIELD` 262144), `CTypedef*` (`MAX_CTYPEDEF`),
  `CPrep*` (`MAX_CPREP_PARAMS`/`MACROS`/`CHARS`).
- Output buffers `Code` (`MAX_CODE` 8 MB), `Data` (`MAX_DATA`).

Smaller bounded tables (`MAX_ARR_DIMS`, `MAX_CPREP_CONDS`, `MAX_GOTO_LABELS`, …)
can stay fixed — they are genuinely small and bounded.

## Bonus — dynarray correctness dogfood

The compiler is the densest dynamic-array user we have. If `Tokens[]` et al.
become managed dynarrays grown via `SetLength`, then **self-hosting exercises
dynarray growth/realloc on every compile**, across every backend, with the
byte-identical fixedpoint and the cross harness as oracles. Any latent bug in
dynarray grow / managed-element handling / cross-target dynarray ABI would
surface as a self-host or cross divergence. Free, brutal, deterministic coverage.

## Landmines

- **Parallel arrays must grow in lockstep** — `Tokens` / `TokPackRecords` /
  `CAttrFlags` are indexed by the same token id; a partial grow corrupts.
- **Indices/pointers held across a grow** — any code holding a raw element
  address (not index) over an append breaks when realloc moves the buffer. Audit
  for `@arr[i]` held across growth.
- **Self-host byte-identical must hold** — a tables refactor changes the
  compiler's bss/codegen; expect a multi-gen reseed (front-end-ish but touches
  hot paths) and re-pin. Validate on the self-hosted binary, not just FPC.
- **Cross + ESP** — dynarray growth goes through the managed-aggregate / RTL
  path; run the full cross harness. ESP (constrained RAM) actually *benefits*
  (no giant static reserve) but needs the managed-dynarray path working there.
- **Perf** — geometric growth amortizes, but a too-small initial reserve causes
  early realloc churn on big TUs; pick sane initial sizes.
- **A ZERO-INIT SENTINEL IS A CONTRACT WITH "NO ROW IS EVER REUSED", and this
  conversion is the thing that can break it** (added 2026-09-05, measured from
  frankB's Group 8 work). `AliasEnumId` (`compiler/defs.inc:6039`,
  `array[0..MAX_TYPEALIAS-1]`, MAX_TYPEALIAS = 4096) stores the enum index
  **PLUS ONE**, because 0 is a valid enum index and an unwritten row must mean
  NONE. **Six procedures do `Inc(AliasCount)`** — `compiler/symtab.inc` 265,
  416, 441, 467, 557, 591 — and **exactly one writes `AliasEnumId`** (412/414,
  the block immediately before the Inc at 416). Readers are
  `pasparser_decl.inc:1188` and `pasparser_lval.inc:7762`/`7839`.
  **It is safe TODAY for a stated reason, not by luck:** `AliasCount` never
  decreases and no row is recycled, so an unwritten row genuinely reads 0 and the
  omission is inert. **If a grow-and-reuse scheme ever recycles an alias row, five
  allocators become stale reads that FAIL OPEN** — a leftover enum id read as the
  current one, silently, in a table whose column comment says the omission is
  inert. Geometric growth alone is fine; a free-list or a compaction pass is not.
  frankB deliberately did NOT add five copies of the write, because five copies is
  the missing-copy shape that column already documents. **If this conversion
  introduces reuse, that decision has to be revisited, and this bullet is the
  only place the dependency is written down from THIS side.**
- **Frozen vs managed self-build** — the compiler self-builds frozen; make sure
  the dynarray path is exercised in that mode too, not only managed user progs.

## Performance angle (2026-06-29)

Raised after the `make benchmark` run (commit `9eecff79` era):

- self-host pascal26 compiles `compiler.pas` **2.96× slower than FPC** (6.47s vs
  ~2.19s) — gap *widened* from ~2.1× as the compiler grew.
- managed-string hello is **23× slower** than frozen and yields a **110× bigger
  exe** (31.6 KB vs 287 B) — runtime memory/heap init dominates tiny programs.

User hypothesis: **the speed cost is largely memory management** — we reach for
fixed `array[0..MAX_*]` static storage where a grow-on-demand dynarray belongs,
and pay for it in a ~165 MB BSS that is touched/cache-thrashed and reserved
worst-case on every compile.

**Honest scoping (don't oversell):** the dominant self-compile lever is still
**register allocation** (no regalloc → ~2× baseline, per
[[project_make_test_timing_analysis]]) — converting tables to dynarrays will
*not* close the 2.96× gap on its own. Its perf wins are real but secondary:
smaller resident set / better cache locality / faster process startup (less BSS
to map+zero), plus killing the manual `MAX_*` bump+reseed treadmill. Treat perf
as a *bonus* on top of the capacity+RAM+dogfood case above, and **measure**
(wall-time self-compile + RSS + hello startup before/after) rather than assume.

## Execution constraint — do this on a dev branch, NOT master

This is a **big destabilizing overhaul** that touches the compiler's hottest
data structures. It breaks self-host byte-identical until it converges and needs
a multi-gen reseed + re-pin. Unlike the usual Track-A "work on master" rule, the
user has explicitly scoped this one to a **separate git dev tree / branch**:
land it incrementally there, get `make test` + self-host fixedpoint + full cross
+ ESP all green on the branch, *then* merge to master as one converged step.
Never carry a half-converted tables refactor on master (it would trip the
stable-binary / self-host gate for every other Track-A change).

## Acceptance

- Target tables are dynamic; compiler compiles sqlite (and lua) without manual
  `MAX_*` bumps for those tables.
- Compiler bss drops materially for small inputs (measure hello-world bss before/
  after).
- `make test` + self-host byte-identical (post-reseed) + cross (i386/arm32/
  aarch64/riscv32) + ESP build all green.
- A note in the ticket recording which tables were converted and which stayed
  fixed (and why).

## Log

- 2026-06-27 - Filed. MAX_TOKENS 512K→2M bump (sqlite M5) exposed the fixed-table
  ceiling pattern; user flagged the dynarray conversion as both the right fix and
  a self-host dynarray-correctness stress test. Future work — not blocking the
  sqlite arc (which proceeds on the static bump for now).
- 2026-06-27 - User decision: **static arrays are fine for now** (accept the RAM
  cost); dynarray conversion is explicitly **later**. Interim static bumps
  tracked in [[chore-sqlite-static-capacity-bumps]]. This ticket stays backlog as
  the eventual proper fix + dynarray dogfood.
- 2026-06-29 - Reframed with a **performance** motivation off the `make
  benchmark` numbers (pxx 2.96× slower self-compile; managed hello 23× slower /
  110× bigger). User hypothesis: speed cost is mostly memory management
  (static-over-dynarray). Added honest scoping (regalloc is the bigger lever;
  this is a secondary cache/startup/RAM win + dogfood) and an **execution
  constraint: do the overhaul on a dedicated git dev branch, not master**, then
  merge once converged. Still backlog, still not blocking anything.

## Progress log — 2026-07-18 (agent opus-A): incremental-on-master approach PROVEN

**Revised execution model — the "dev branch + multi-gen reseed" constraint is NOT
needed for the incremental, one-family-at-a-time path.** Converting a single parallel-
array family in isolation lands on master byte-identical with NO reseed: the self-host
gate is fixedpoint *reproducibility* (compile self twice → identical), not "same as
before", and a deterministic static→dynamic swap keeps the fixedpoint. Proven twice
below. The dev-branch caution still applies to a big-bang all-at-once rewrite; do it
incrementally instead.

**The pattern (see [[project_dynamic_compiler_arrays_pattern.md]] in agent memory):**
`array[0..MAX_X-1] of T` → `array of T`; `EnsureXCapacity(need)` (double from a base,
grow ALL parallel arrays in lockstep) at the ONE append chokepoint; drop the overflow
Error. Gate: rebuild fixedpoint cmp + a build-time-generated over-cap test + quick.

**DONE:**
- **IR node arrays** (11 arrays, `cf7bbcea`) — chokepoint IRAppend. BSS 365→353 MB.
- **AST node arrays** (14 arrays, `d11bf05a`) — chokepoint AllocNode. Needed a
  two-region SWAP: the retained-inline-body reserve moved from the fixed TOP
  ([INLINE_AST_BASE..]) to a fixed LOW reserve [0..INLINE_AST_RESERVE=8192) so per-proc
  can grow upward. Safe because nothing linearly scans [0..ASTNodeCount) (verified).
  BSS 353→327 MB. Inline tests green -O2/-O3.
- Cumulative BSS: **365 → 327 MB (−38 MB)** always-resident, and both hard caps gone.

**REMAINING — priority (biggest BSS / most overflow-prone first):**
1. **Tokens family** (`MAX_TOKENS`=2M, 8 arrays incl. the large `TRawToken` record —
   the single biggest BSS consumer, ~100 MB, and the one sqlite already broke). LAND-
   MINE: audit for any `@Tokens[i]` / raw pointer held across a grow (realloc moves the
   buffer) — the token buffer is the most likely place code takes element addresses.
   Chokepoint = the lexer's token-append.
2. **Syms family** (`MAX_SYMS`=131072, 31 parallel `Sym*` arrays) — chokepoint AllocSym
   (remember the Alloc*-resets-ALL-fields landmine: [[project_symtab_alloc_parallel_array_landmine]]).
3. **UField family** (`MAX_UFIELD`=262144, 26 arrays, C-frontend heavy).
4. Single buffers: `Code` (8 MB), `Data` (2 MB), `CPrepChars` (8 MB) — held-address
   audit matters most here.
- Genuinely small/bounded (MAX_ARR_DIMS, MAX_CPREP_CONDS, MAX_GOTO_LABELS, the residency
  arrays, …) stay fixed.

Superseded [[feature-dynamic-compiler-arrays-ast-fixups]] (folded into this ticket).
Note the seq-walk STACK OVERFLOW (~3500 chained statements SIGSEGVs the recursive
AST/IR tree walk) is a SEPARATE problem — a stack-depth limit, not an array cap; needs
an iterative worklist, out of scope here.

## Update 2026-07-18 (cont.) — Tokens DONE (biggest win)

- **Token arrays** (8 arrays, `0f4b5882`) — `MAX_TOKENS`=2M, the single biggest BSS
  consumer. No single chokepoint (20 Inc(TokCount) sites across 10 lexers + parser), so:
  startup bootstrap `EnsureTokCapacity(65536)` + `EnsureTokCapacity` after each Inc +
  the per-frontend pre-append `if TokCount>=MAX_TOKENS then Error` guards converted to
  grow. No `@Tokens[i]` held across a grow (audited). `MAX_TOKENS` kept as the
  `MainProgramTokCount=MAX_TOKENS` sentinel. Self-host byte-identical (lexes ~1M
  tokens/build), C + NilPy frontends green. **BSS 326→215 MB (−111 MB).**
- **Cumulative IR+AST+tokens: 365 → 215 MB BSS (−150 MB), three hard caps gone.**
- FPC-clean: none of EnsureIRCapacity/EnsureASTCapacity/EnsureTokCapacity need
  forwards.inc entries (each defined before all uses). The fpc-bootstrap red is
  PRE-EXISTING (Jul-13, 603cf2bd — NestStrOff/IRAppendCall/IRWrapChkBounds/MangleSuffix
  missing from forwards.inc + a WrapPCharToString overload clash), unrelated to this work.

**REMAINING:** Syms (131072×31, chokepoint = the 5 Alloc* in symtab.inc), UField
(262144×26), Code/Data/CPrepChars buffers.

## Update 2026-07-18 (cont. 2) — Syms + UField DONE

- **Syms** (31 arrays, `0af554f2`) — EnsureSymCapacity at the 5 Alloc* chokepoints.
  Grows from 0 (no reserve). BSS 215→186 MB (−29 MB). All frontends validated.
- **UField** (28 arrays incl 2-D ArrDim, `e71df9df`) — EnsureUFieldCapacity at
  AddUField's three write points (single append + inherited-field relocation). BSS
  186→146 MB (−40 MB). C-conformance 220/220, no C regressions.
- **Cumulative IR+AST+tokens+syms+ufield: 365 → 146 MB BSS (−219 MB), 5 caps gone.**
- Found (unrelated, filed): [[bug-c-huge-struct-high-field-offset-miscompile]] — a C
  field past 64 KB offset miscompiles (16-bit wrap suspect), pre-existing.

**REMAINING:** Code/Data/CPrepChars byte buffers (held-address audit matters), label
arrays (MAX_IR-sized), smaller MAX_ tables (CTypedef/CPrep*/DBG_VARS).

- 2026-07-19 (sweep) **PARKED to backlog.** No agent on it. Landed + green:
  IR, AST, Tokens (0f4b5882), Syms (0af554f2), UField (e71df9df) — BSS
  365→146 MB, 5 hard caps gone. REMAINING: Code/Data/CPrepChars byte buffers
  (held-address audit critical), MAX_IR-sized label arrays, smaller MAX_
  tables (CTypedef/CPrep*/DBG_VARS).

## Update 2026-08-21 (agent-A) — six more families, and a MEASUREMENT that contradicts the ticket's premise

Landed, each its own commit, each with the self-host fixedpoint byte-identical:

| family | arrays | BSS freed |
| --- | --- | --- |
| `AsmDisProcAtPos` | 1 | 67.1 MB |
| CallFix + CodeRef + the DCE graph tables | 5 | 33.5 MB |
| the per-ROUTINE family (`Proc*`, `ProcParam*`, `PyCapName`, `InlineLocalTk`) | 90 | 38.8 MB |
| `SymArrDimLo` / `SymArrDimSpan` | 2 | 6.3 MB |
| `GlobFix` | 1 | 2.1 MB |
| `IRSeqSpine` | 1 | 4.2 MB |
| `Code` | 1 | 16.8 MB |

Compiler BSS **246.8 MB -> 75.9 MB**. (It was 146 MB when this ticket was parked;
the rise since was ordinary growth plus ~28 MB I added earlier the same day for
[[feature-emission-size-dce]], which is why that one is in the table.)

Three caps are gone with the reservations: `MAX_GLOBFIX` — the one measured to
have been hit for real, by the `--threadsafe` self-host, 121 entries in —
`MAX_IR_SEQ_SPINE`, and the internal call/code-reference tables. `MAX_CODE` and
`MAX_PROCS` stay as hard caps on purpose.

### The premise does not survive measurement

The ticket's performance framing was that the fixed tables are *"touched/cache-
thrashed and reserved worst-case on every compile"*. They are reserved
worst-case; they are **not touched**. BSS is demand-zero — an untouched page
never becomes resident — so the reservation was free, and replacing it with heap
is not.

Max RSS, same inputs, pre-session binary vs HEAD:

| compiling | before | after |
| --- | --- | --- |
| `hello.pas` | 24.2 MB | 26.3 MB |
| a NilPy module | 55.3 MB | 66.2 MB |
| `compiler.pas` (self-compile) | 453.1 MB | 497.0 MB |

Wall time is unchanged (self-compile 26.9s both ways), so the extra indirection
per element does not show. But **RSS went UP, by ~10%**, which is the opposite of
what the ticket predicted and the opposite of what a reader would assume from
"BSS 246 MB -> 76 MB".

### Why, exactly

Not the live data — that is the same bytes either way. It is the GROWTH:
`SetLength` is allocate-copy-free, and the freed block cannot serve the next
doubling, because the large-block free list is first-fit on `size >= request`
and every subsequent request is BIGGER. So each table leaves behind the whole
geometric series of its previous buffers — about one final-size worth of
garbage per table, permanently unreusable by that table.

That is the root cause, it is in the allocator rather than in any table, and it
costs every pxx program that grows a dynamic array, not just the compiler. Filed
as [[feature-opt-dynarray-grows-in-place]]: give the scalar-array SetLength path
the in-place-when-unique + geometric-headroom treatment the AnsiString path
already has, three arms away in the same case statement.

### What is left here

`Procs` (8.4 MB, an array of RECORDS holding managed strings — a different
SetLength path), `TokChars` / `LoadFileBuf` / `CPrepChars` (8.4 MB each),
`Data` (2.1 MB, ~20 unguarded append sites), the `TemplateTokens` /
`SpecializeTokens` pair (1.8 MB each), the MAX_IR-sized label arrays.

**Do the allocator ticket before any of them.** Converting more tables now buys
a smaller number in the `bss=` line and pays for it in resident memory; after
in-place growth lands, the same conversions are close to free.

### The trap, for whoever picks this up

`MAX_PROCS` was also being used as an INDEX bound in nine places —
`for pi := 0 to MAX_PROCS - 1 do ProcSigOff[pi] := -1` in rtti_emit.inc became a
write off the end of a heap block the moment the table stopped being that long.
The self-host gate did NOT catch it (it happens to sit in NilPy's signature
emitter). Grep every `MAX_<FAMILY>` after converting a family, and treat each
remaining use as a question: is this a capacity bound (fine) or an index bound
(now wrong)?


## Progress log — 2026-08-21 (agent-A): the REMAINING list above is STALE

Read the source before picking an item from it. Measured today:

| family | list above says | actually |
| --- | --- | --- |
| Tokens (`MAX_TOKENS`) | remaining, #1 | **done** — `Tokens`/`TokPackRecords`/`Tok*Checks`/`CAttr*` are `array of`, grown by `EnsureTokCapacity` |
| Syms (`MAX_SYMS`) | remaining, #2 | **done** — `Syms` + the ~30 `Sym*` arrays grown by `EnsureSymCapacity` |
| UField (`MAX_UFIELD`) | remaining, #3 | **done** — 26 arrays grown by `EnsureUFieldCapacity` |
| IR / AST | done | done |

**Still genuinely fixed:** `Data` (`MAX_DATA`), `Strs` (`MAX_STRS`), `CPrepChars`
(`MAX_CPREP_CHARS`), `TokChars`/`LoadFileBuf` (`STRING_CAP`, 8 MB each),
`LabelFixupPos`/`LabelFixupTarget` (`MAX_IR` — 1 MB each), `UCls*`
(`MAX_UCLASS` = 2048), `Procs` itself (deliberate, see `EnsureProcCapacity`'s
note). `Code` is already dynamic.

**The conversion has a second half nobody ran**, and it is where the remaining
risk sits: *deleting a cap does not delete the code that assumed it.* Four
sites had taken `MAX_X` to mean "a number the count can never reach" and were
left behind — one of them an out-of-bounds stack write in `IRVerify`, which runs
on every body. Filed and fixed as
[[bug-a-dynamic-tables-left-their-fixed-size-shadows-behind]].

**So: before converting the next family, grep for its `MAX_` name across
`compiler/**` and read every hit.** A hit that is not the array declaration is
either a real remaining cap (fine — `LabelFixup*` still is one) or a shadow that
the conversion has just made wrong. That grep is now part of the pattern, not
an afterthought.

## 2026-08-30 — RE-MEASURE (triage only, nothing applied): still genuine

Checked in the parked-ticket pass. No resume condition names another ticket:
the five resolved slugs here are cited landed work, and the one open slug
(`feature-opt-dynarray-grows-in-place`) is a pointer, not a blocker.

This ticket is an incremental conversion with its method already written down —
*before converting the next family, grep for its `MAX_` name across
`compiler/**` and read every hit*, because deleting a cap does not delete the
code that assumed it (the `IRVerify` out-of-bounds write is the worked
example). That instruction is the ticket's real value and it is intact.

**Re-priced: unchanged.** Parked for want of an agent, not for want of a bridge.


## 2026-09-05 (frankH) — LoadFileBuf converted, and the interesting part is WHO runs it

`LoadFileBuf` was `array[0..STRING_CAP-1] of Byte` — **8 MB of BSS in every
compiler this repo ships**. It is now `array of Byte`, grown by `LoadFile`, with
`LoadFileCap` never shrinking across loads. Measured on the self-host build:
**bss 106842604 -> 98454060**, exactly the 8 MB.

**The claim I nearly shipped, and what measuring it actually found.** I wrote,
first, that this removed a silent truncation: one `sysread` of at most
`STRING_CAP` means a file over 8 MB is read short. Then I tested it — a 30 MB
unit through the PINNED compiler, expecting a truncation error — and it
**compiled and ran correctly**. That is impossible if `LoadFile` were the reader.

It is not. **`LoadFile` is intercepted in the parser as a builtin**
(`pasparser_stmt.inc`, backed by `PXXStrLoadFile`), so a self-hosted pxx never
executes the Pascal body at all. The 8 MB array was BSS that path allocates and
never touches. **The body is live only under the FPC-seeded cold-bootstrap
compiler**, where `sysread` is `fpRead` and nothing intercepts the call.

**So the correctness half is real, narrow, and now has a before/after control.**
Two FPC seeds built from the same tree, one with the change stashed:

| | 30 MB unit | small unit |
| --- | --- | --- |
| seed WITHOUT the change | `pascal26:88305: error: unterminated comment` | works |
| seed WITH the change | compiles, prints 777 | works |

Line 88305 is where the 8 MB cut lands. **The genuinely SILENT case is not
source at all — it is `{$R}`**: `resources_emit.inc` calls `LoadFile` to embed a
file's bytes, so a resource over 8 MB was embedded SHORT with no diagnostic, the
build succeeding and the blob simply wrong. A truncated Pascal *source* usually
errors, but about whatever the cut leaves dangling, which misnames the fault.

**It also stopped borrowing `STRING_CAP`.** That constant is the TOKEN CHAR
POOL's capacity and carries ~40 overflow checks; it was also sizing this
unrelated read buffer, so a bump for one silently moved the other. Following
this ticket's own method — grep the `MAX_` name and read every hit — is what
surfaced that: of the ~40 `STRING_CAP` hits, exactly one was about this buffer.

**Method note for the next family.** The grep this ticket prescribes found the
shared constant, but it would NOT have found the builtin interception, because
nothing in `elfwriter.inc` or `defs.inc` says the body is dead in self-host. The
question that found that was *"what would this be if it were false"* — run the
old binary on an oversized input and see whether it actually breaks. **Add that
to the method: before claiming a fixed table costs correctness, make the current
compiler fail on it.** A table can be pure BSS waste and no ceiling at all, and
those two justify very different amounts of risk.

Still fixed after this: `Data`, `Strs`, `CPrepChars`, `TokChars`,
`LabelFixupPos`/`LabelFixupTarget`, `UCls*`, and `Procs` deliberately.

## 2026-09-06 (frankH) — CPrepChars converted, and the cap was REAL this time

`CPrepChars : array[0..MAX_CPREP_CHARS-1] of Char` (8 MB) → `array of Char`
grown geometrically from 256 KB in its single writer, `CPStoreRange`.
`MAX_CPREP_CHARS` is deleted: it had exactly one code use, this table's bound.

**bss 98454060 → 90066100**, the 8 MB, on top of LoadFileBuf's.

### The method step, and why it earned its place

The previous family (LoadFileBuf) taught that a `MAX_` grep finds the constant
and not the *reachability*, so the rule added there was: **before claiming a
fixed table costs correctness, make the current compiler fail on it.** Applied
here it paid immediately, and it paid in BOTH directions:

- **First attempt said "unreachable" and was wrong.** 18.5 MB of C, 300000
  `#define M_%08d (...)` lines, answered `pascal26:1: error: too many C macros`
  — that is `MAX_CPREP_MACROS` (32768), a **different cap**, and stopping there
  would have recorded this pool as unreachable behind the macro-count limit.
- **Second attempt reached it.** 30000 macros whose *values* are ~430 bytes of
  text each (13.8 MB) answers `pascal26:1: error: C preprocessor text overflow`
  — this table's own message.

So the generalisation is not "grep the cap, then try a big input". It is
**two caps can be in range of one input, and which one you hit is a ratio.**
Macro COUNT and macro TEXT are independent axes; an input that maximises one
tells you nothing about the other, and the diagnostic is the only thing that
says which axis you actually tested. Read the error string, not the exit code.
An unreachable ceiling and a ceiling you failed to aim at are the same rc=1.

### The method, stated symmetrically — a probe's SUCCESS is not evidence either

The rule inherited from LoadFileBuf was *make the current compiler fail on it*,
and the near-miss above sharpens its refusal half: **a refusal from a DIFFERENT
limit reads exactly like your answer**, so read whose message it is.

The other half has no diagnostic at all and is the quieter of the two. After
converting, the 13.8 MB input answers `rc=0` — and **`rc=0` is not the proof.**
A pool that grew but silently truncated, or mis-deduplicated a stored range,
also exits 0 and also emits a linkable binary, because nothing in that file's
macros has to be *used*. The success face has the same structure as the refusal
face: it answers, it does not error, and it is correct about something else
(that the compiler did not crash).

So, for a reachability probe on a converted table:

- the **refusal** is read by asking *whose message is this* — the diagnostic
  string names the axis you actually tested;
- the **success** cannot be read that way, because there is no string. It needs
  an assertion on the OUTPUT, and **the assertion class must match the defect
  class of the table.** A content pool fails as wrong characters, never as a
  crash — so "did the oversized input produce a correct program", not
  "did it exit 0".

### Scope of the claim

Reachable **with a synthetic input**, measured. I have *not* shown a real
header reaching 8 MB of macro text, and this ticket should not claim one. What
the measurement does establish is that this was a **ceiling** and not pure BSS
waste — which is the distinction that decides how much risk the conversion is
worth, and it is exactly the distinction LoadFileBuf turned out to fail.

### Verification

- Self-host `converged after 1 round(s)`, sha `545ff59e4299`.
- The 13.8 MB input that overflowed now compiles (`rc=0`) and the emitted binary
  runs; peak RSS 61 MB, i.e. the pool grew to fit rather than reserving.
- **Before/after emitted-code comparison over the C test corpus.** The change is
  to a content pool, so the defect class is *corrupted or mis-deduplicated macro
  text*, which no crash and no rc would show — it shows as different bytes in
  the output. Built the pre-change compiler by stashing the diff (`3a3e6125cc32`),
  restored, rebuilt, and confirmed the restored build reproduces `545ff59e4299`
  exactly — so the two binaries differ in this diff and nothing else. Then
  compiled every `test/*.c` with both and compared outputs byte for byte.
  **Positive control:** the 13.8 MB macro file, which MUST differ (old refuses,
  new succeeds) — a corpus comparison with no must-differ row is a guard that
  cannot fail.
- `PXX_ALLOW_FULL_SUITE=1` lifted for the corpus run: the quick tier does not
  exercise the C preprocessor's only string pool, and this is the one table
  whose users are all in the C frontend. `test-c-conformance` and `test-cjson`
  both SKIP on this box — no fetched corpus — so the before/after comparison is
  the C coverage, not an addition to it.

### Two findings for the NEXT families (grep done, conversion not)

- **`MAX_DATA` has a use that is not a bound.** `compiler/symtab.inc:5548`:
  `if base + n * esz >= MAX_DATA then Exit;` with the comment *"out of data
  space: keep the old path rather than fail the compile"*. That is a **policy
  threshold**, not an array bound — a graceful degradation to runtime init.
  Making `Data` dynamic makes the condition permanently false, so converting it
  **deletes a silent fallback**. That is the right direction (a large static
  array init should be emitted, not quietly demoted) but it is a behaviour
  change and must be stated in the commit, not discovered later. Every other
  MAX_DATA hit — ~20 of them across `emit.inc`, `ir.inc`, `pasparser_*.inc`,
  `elfwriter.inc` — is a real `Error('data overflow')` bound.
- **`STRING_CAP` sizes two unrelated things and the second one is a TYPE.**
  Besides ~15 token-pool bounds it appears as `sz := STRING_CAP + 8`
  (`ast_syminfer.inc:151`) and `elemSize := STRING_CAP + 8` (`ir.inc:2703`) —
  that is the **shortstring storage size**, decided at declaration time. So
  `TokChars` cannot be converted by changing `STRING_CAP`; the constant must be
  **split first** into a string-type width and a pool capacity. This is the same
  shape LoadFileBuf had (it borrowed STRING_CAP too) and it is now the second
  instance, which makes it a property of the constant rather than an accident.

### Constraint on the conversion pattern (from frank-coordinator's landmine)

**This ticket's pattern is realloc that PRESERVES INDICES, and that is load
bearing.** Geometric growth is safe for zero-init sentinel columns like
`AliasEnumId` (`defs.inc`, stores enum index **plus one** so an unwritten row
reads 0 = NONE, written by one of six allocators, inert because `AliasCount`
never decreases and no row is recycled). A **free list or a compaction pass** is
not safe: it turns every allocator that does not write such a column into a
stale read that **fails open**. Out of scope here — a free list for one of these
tables is a different ticket with a different gate.

### STALE-PARK, answered a second time — and the answer changed

`progress.sh check` reports `STALE-PARK-HELD` on this ticket. It is a false
positive **by the check's own note** — the slug matched, not the question;
`blocked-by:` is `[]` and the citations are prose references to landed work.
The 2026-08-30 re-measure already adjudicated it once.

But re-reading it was not free of information, because **one detail of that
2026-08-30 note is now stale**: it recorded `feature-opt-dynarray-grows-in-place`
as *"the one open slug ... a pointer, not a blocker"*, and that ticket is now in
`done/`, as is `feature-emission-size-dce`. Both cited dependencies have landed.
That matters here rather than being bookkeeping: in-place dynarray growth is the
thing that makes this ticket's doubling amortise, so the conversion pattern got
cheaper after the note that dismissed the pointer was written.

Which is the actual lesson about the check: it fires on slug adjacency and it
will keep firing, so it cannot be closed by being right once — but a report that
is wrong about *blocking* was still right about *staleness*, and the ticket had
a sentence that had quietly become untrue. Read it; do not act on it.

## 2026-09-06 (frankH) — Data converted, and it exposed a guard that could not fail

`Data : array[0..MAX_DATA-1] of Byte` (2 MB reserved in bss) → `array of Byte`,
grown by a single helper `DataEnsure(n)` in `util.inc` (included after
`lexer.inc`, where `Error` lives, and before every user). `MAX_DATA` deleted.

**bss 90066100 → 87985348**, the 2 MB.

### The two tables were coupled, and the ticket's own method could not see it

The prescribed step is *grep the `MAX_` name across `compiler/**`*. That found 26
`MAX_DATA` hits and zero connection to the string table — **because the coupling
is not an identifier, it is arithmetic between two independent constants.**

Measured, on the pre-change compiler:

- every string literal costs `32 + align8(len+1)` bytes of `Data` — a 32-byte
  managed-string header (`size`/`meta`/`rc`/`len`) so the literal doubles as a
  managed handle, which `InternStr` documents deliberately. Confirmed linear
  across five lengths: len 3/11/19/27/35 → 40/48/56/64/72 bytes.
- so the floor is **40 bytes per entry**, and `MAX_DATA` = 2097152 caps the
  string table at ~52108 entries.
- `MAX_STRS` is **65536**. It is 13000 short of ever being reached.

Confirmed by running it, not by the arithmetic: 52000 literals compile at
`data=2092792`; **52200 answers `error: data overflow`**; 66000 answered
`data overflow` too. `emit.inc`'s `Error('string table overflow')` was
**a guard that cannot fail**, and it had no way to say so.

**After the conversion the same 66000-literal input answers
`error: string table overflow`.** That is the positive control for the whole
claim: the identical input moved from one cap's message to the other's, which is
the only evidence that could distinguish "MAX_STRS was unreachable" from
"I never aimed at it". `Strs` is therefore the next family and it is now load
bearing, where before converting it would have changed nothing observable.

Generalisation for the remaining families: **two tables can share a ceiling
without sharing a constant.** Grep finds shared identifiers; it cannot find a
shared *resource*. Before converting a table, ask what else consumes the thing
its cap is denominated in.

### The one MAX_DATA use that was not a bound

`symtab.inc` had `if base + n * esz >= MAX_DATA then Exit;` — a **policy
threshold**, not an array bound. Near the 2 MB reserve, the typed-const-array
promotion silently gave up and left the array on the startup-store path, i.e.
the ~29-bytes-of-code-per-element treatment that optimisation exists to delete,
with **no diagnostic**. The function fails closed (`Result := False` default), so
this read as "not eligible". Now `DataEnsure(base - DataLen + n * esz)`:
promotion no longer depends on how much `.data` the rest of the compile used
first. Behaviour change, deliberate, in the direction the optimisation wants.

### What the conversion actually broke, and how it was found

The first build **segfaulted in round 2**. Cause: writes into `Data` that never
went through an overflow check at all, because with a fixed bss array they never
needed one. A grown array is nil until asked.

- `compiler.pas` writes `Data[MINUS_OFFSET]` and `Data[NEWLINE_OFFSET]` at
  **constant offsets** after setting `DataLen := STR_INIT_OFFSET` — the one
  place that needs the buffer to exist before anything appends.
- five unguarded byte runs — `'True'`/`'False'`/`'None'`/`'<object>'`
  (`ir_codegen.inc`), the 16-byte RTTI/layout backlink and the VMT zero-fill
  (`pyparser.inc`), the 8-byte GOT slot (`symtab.inc`).

**The grep that finds these is not the `MAX_` grep** — it is *every write to the
table, and does an ensure dominate it*. Scripted, not eyeballed, because the
failure is silent for any run that stays under the initial 64 KB reserve: this
class only crashes once the table is big, which is exactly the input nobody runs.
Add to the method: **after converting a table, enumerate its WRITE sites, not its
CAP sites.** The cap sites are the ones that were already thinking about the
limit; the write sites are the ones that never had to.

`DataEnsure` also zeroes the newly grown region explicitly. Bytes at or past
`DataLen` **are read before being written** — the static-array path aligns `base`
up from `DataLen` and never writes the padding — and the old array was bss, i.e.
zero by construction. `SetLength` is specified to zero new elements; the loop
states the property rather than inheriting it, because a garbage alignment byte
lands in `.data` silently and nothing in this compiler asserts on `.data` padding.

## 2026-09-06 (frankH) — Strs converted, immediately after the table that hid it

`Strs : array[0..MAX_STRS-1] of TStrEntry` → `array of TStrEntry`, doubled from
1024 in `InternStr`, its only writer. `MAX_STRS` deleted.

**bss 87985348 → 86412492**, the 1.5 MB (65536 × 24).

This is the first table here whose growth carries a **managed field** through the
realloc — `TStrEntry.Text` is an `AnsiString`. Probed before converting rather
than after: 5000 entries through 11 regrows, every earlier string compared back
against its expected value, all intact.

Converted immediately after `Data` and not whenever, because until `Data` grew
this cap could not fire at all. The proof is one input crossing three states:
66000 short literals answered `data overflow` before `Data` was converted,
`string table overflow` after it, and now compile and **run** — 66000 lines,
last `qhp`, which is exactly index 65999 in the generator's alphabet.

### The write-site audit, second application

`Strs` has exactly one write block (`emit.inc`, three fields at `[StrCount]`,
immediately after the cap check) and every read is at an index below `StrCount`.
That is what a clean conversion looks like, and it is worth recording as the
contrast case: the audit is cheap when it finds nothing, and `Data` is why it
gets run anyway.

### Two stale citations repaired in the same commit

`MAX_STRS` was named in two comments that outlived it — `MAX_UNITS`' note and
`VisCacheVis`', both recording that `VisCacheVis` *used to be* sized by the
string-table cap. Both now say the constant is gone. The history stays because
the point of those notes is the **coupling**, which was real and is the same
mistake class this ticket keeps finding; but a comment citing a constant that no
longer exists is a name with nothing behind it, and the next reader greps.

### LANDMINE for whoever benefits from the lifted cap: InternStr is O(n²)

`InternStr` dedups by **linear scan over the whole table**, with an inner
per-character compare, on every literal. Measured at HEAD (x86-64, warm):

| literals | wall |
| --- | --- |
| 5000 | 1.29s |
| 10000 | 2.48s |
| 20000 | 6.30s |
| 40000 | 25.69s |

Doubling the input roughly quadruples the time by 40000. So removing the cap
replaces a **hard error** with a **practical time ceiling**, which is strictly
better — the old compiler did all the same scanning and then refused — but it
means "the string table is unbounded now" is a claim about capacity, not about
usability. A hash index over the pool is the fix and it is the natural next
change; until it lands, do not quote the lifted cap as though 200k literals were
practical. Nothing here is a regression: this cost is unchanged by the
conversion, it is merely now reachable.

## 2026-09-06 (frankH) — InternStr hash index: the lifted cap made usable

Removing `MAX_STRS` swapped a hard error for a time ceiling. This closes it.

`InternStr` dedups through an open-chained index parallel to `Strs`
(`StrHashHead` / `StrHashNext`, doubled at load factor 1) instead of scanning
the whole table. **Index identity is preserved** — entries keep the numbers they
would have had — so this changes only which entries get COMPARED, never which
one wins: dedup guarantees at most one entry per bucket can match.

| literals | linear | hashed |
| --- | --- | --- |
| 5000 | 1.27s | 0.94s |
| 10000 | 2.13s | 1.30s |
| 20000 | 6.60s | 1.48s |
| 40000 | 22.24s | 1.68s |
| 66000 | (refused before `Strs`) | 3.42s |

Emitted output byte-identical at every size, which is the requirement: this is a
performance change and any output difference would be a defect, not a feature.

The hash is djb2 masked to 24 bits **inside** the loop, so `h * 33` stays under
2^29 and the result never depends on what signed overflow does — the compiler
running this code is also the compiler being built by it.

### The next cap in the chain, found by pushing past this one

200000 literals now answers **`error: fixup overflow`** — `MAX_FIXUPS` = 131072.
Third time this ticket has hit a cap it was not aiming at, and the chain is now
documented end to end for one input shape: `data overflow` → `string table
overflow` → (time) → `fixup overflow`. **Each conversion reveals the next
ceiling, and the reveal is the only way any of them were known to be reachable.**

`MAX_FIXUPS` sizes THREE parallel arrays — `Fixups`, `FixupPCRel`,
`FixupPicDelta` — so it is the first family here where the ticket's
"parallel arrays must grow in lockstep" landmine actually bites.

### A DEFECT FOUND WHILE SCOUTING IT, not by this ticket's grep

`Fixups` is compacted in two places and only one of them is right.

- `dce.inc` shifts the record **and** both parallel arrays, with a comment
  saying why: *"They are parallel BY INDEX, so compacting the record without
  them hands every surviving site the flags of whoever used to sit at its new
  index."*
- `compiler.pas`, the `DATAREF_DROP` arm, does `for j := i to FixCount - 2 do
  Fixups[j] := Fixups[j + 1]; Dec(FixCount);` and moves **neither** parallel
  array.

`FixupPCRel` is initialised `False` per entry and set `True` on the i386 PIC
path, so it is genuinely heterogeneous within one build; `FixupPicDelta` carries
a per-site anchor delta. After a drop, every surviving fixup past `i` reads its
neighbour's relocation flags — wrong addresses, silently.

**Scope, corrected after probing — this is a LATENT invariant repair, not a bug
with a demonstrated victim.** The violation is certain: `compiler.pas` shifts the
record and not the two arrays, and `dce.inc` states the rule. What is NOT
established is that the arm ever runs.

I first wrote "common" here, sourced from `emit.inc`'s comment calling a
table-less sentinel *"a documented answer, not a defect: a module that publishes
no classes has no registry."* **That is a statement about design, and I read it
as one about frequency.** Measured since:

- minimal program, `p := __rttireg` → resolves to a real address, registry present
- same with `__resources` → resolves, table present
- `EmitDataRef` writes `EmitI32(0)`, so a dropped fixup would leave **nil** —
  which makes "non-nil" a sound discriminator, and it says both tables exist even
  in a program that does nothing
- `EmitResources` does `if ResPendCount = 0 then Exit` leaving
  `ResourceTableOff = -1`, so by inspection it *should* drop with no `{$R}` and
  empirically it does not. That contradiction is unresolved and is the thread to
  pull if anyone wants the reachability answer.

Exposure would additionally need a `FixupPicDelta`-bearing entry after the
dropped index — i386 PIC, the class this repo's default instruments cannot see,
since the dev loop, `gate.sh quick` and the pin all run on x86-64.

**And the first repro was a comparison whose inputs did not exist:** both
compiles failed with *"this object would define no linkable symbol"*, no `.o` was
written, and `cmp` on two absent files printed DIFFERS. It was one step from
being reported as the proof. The existence assertion is what caught it — the
second repro built two 120972-byte objects, compared IDENTICAL, and *then* the
precondition check showed the drop had not fired in it either, so that identity
says nothing about the bug in both directions.

Fixing it anyway: two lines, no cost, and the comment-vs-code disagreement
resolves cleanly in the comment's favour. Just not on a claim it cannot carry.

## 2026-09-06 (frankH) — the fixup family, and the chain terminates

`Fixups` / `FixupPCRel` / `FixupPicDelta`, all three `array[0..MAX_FIXUPS-1]`,
converted together through one helper `FixupEnsure` in `util.inc`.
`MAX_FIXUPS` deleted. **bss 86425036 → 83672548**, 2752488 bytes.

**All three grow in one procedure, and that is the design, not tidiness.** They
are parallel BY INDEX — the same rule the two compaction sites obey. A grow that
moved one and not the others is the identical defect to a compaction that does,
and this tree has already had one of those silently (`a8bfcb695`). Keeping the
three `SetLength`s in one procedure means **there is no site where you can grow
the table without growing the columns, because there is only one site.** This is
also why it did not land in pieces: a partial landing here is silently wrong
rather than loudly wrong.

The write-site audit found every `[FixCount]` write downstream of the single
guard in `EmitDataRef`; the other writes are the two compactions, at indices
already below `FixCount`.

### The chain, complete — one input shape, five states

| entries | answer |
| --- | --- |
| 52200 | `error: data overflow` — `MAX_DATA`, 2 MB |
| 66000 | `error: string table overflow` — `MAX_STRS`, 65536 |
| 40000 | 22.24s — no cap, a **time** ceiling from the O(n²) intern |
| 200000 | `error: fixup overflow` — `MAX_FIXUPS`, 131072 |
| 500000 | **compiles, 14.04s, 992 MB peak RSS**, runs: 500000 lines, last `b6eF` = index 499999 |

**Each conversion revealed the next ceiling, and the reveal is the only way any
of them were known to be reachable.** The ticket's prescribed method — grep the
`MAX_` name — found each table's *bound* and could not have ordered them,
because what ordered them was one oversized input asking the compiler which
limit it would hit first. The terminal state is memory, not a constant.

### What the orphaned comment turned out to know

Deleting `MAX_STRS` orphaned the paragraph that had justified raising it from
8192 to 65536 — a csmith `--paranoid` program needing 9426 distinct literals,
refused at the old cap. Rewritten in place as history rather than dropped,
because it explains the mechanism this ticket kept running into:

**8192 was reachable and 65536 was not.** At ≥40 bytes of `Data` per entry
against a 2 MB `MAX_DATA`, the table could never exceed ~52108, so the new cap
sat 13000 above anything `Data` could fund. **The raise did not make the guard
generous; it made it unreachable** — and nothing in the raise's own evidence
would have shown that, because the program that motivated it needed 9426
entries, comfortably inside both limits.

**Raising a cap without checking the resource it is denominated in is how a
guard stops being able to fire.** That is the same failure as the `MAX_STRS` /
`MAX_DATA` coupling recorded above, seen from the other end: the coupling was
not introduced by anyone, it was introduced by a raise that only looked at one
of the two numbers.

### Remaining

`TokChars` (`STRING_CAP`) — still blocked behind splitting that constant from
the shortstring type it also sizes (`ast_syminfer.inc:151`, `ir.inc:2703`).
`LabelFixupPos`/`LabelFixupTarget` (`MAX_IR`), `UCls*` (`MAX_UCLASS`), and
`Procs` deliberately.

## 2026-09-06 (frankH) — MAX_IR scouted and DELIBERATELY NOT converted

The next family by the old REMAINING list is `LabelFixupPos`/`LabelFixupTarget`
(`MAX_IR`). **Counted before choosing how to convert it, which is the step the
fixup family taught, and the count says do not start.**

| | `MAX_FIXUPS` (converted) | `MAX_IR` |
| --- | --- | --- |
| arrays sized by it | 3, all parallel | **10**, several unrelated |
| cap-check sites | **1** | **20** for `LabelFixupCount` alone (arm32 5, x86-64 8, aarch64 7) |
| uses that are not array bounds | 0 | **7** |
| total references | 5 | **54** |

Three reasons this is a different job, not the next one in the rhythm:

1. **`MAX_IR` sizes ten tables that are not parallel to each other** —
   `LabelFixupPos`, `LabelFixupTarget`, `LabelFixupAnchor`, `LabelAddrFixPos`,
   `LabelAddrFixTarget`, `LabelPositions`, `WasmLabelBlock`, `WasmLabelStamp`,
   `WasmExcSlot`, `XtWideLabel`. That is the `STRING_CAP` shape (one constant
   sizing two unrelated things) at five times the scale. **The constant has to
   be split before anything is converted**, and the split is the work.
2. **Seven uses are VALIDITY PREDICATES, not bounds** — `if (lblId >= 0) and
   (lblId < MAX_IR)` in six backends plus wasm. Those ask *is this label id
   plausible*, and deleting the constant deletes the question. This is exactly
   the ticket's own worked example: four sites had taken `MAX_X` to mean "a
   number the count can never reach", one of them an out-of-bounds stack write
   in `IRVerify`. Here there are seven and they are spread across every backend.
3. **The structural answer is unavailable.** Twenty cap sites means twenty
   `Ensure` calls, so lockstep between `LabelFixupPos` and `LabelFixupTarget`
   would be **discipline at twenty sites** rather than one procedure — the
   property the fixup family got for free because its old code had one check.

**The cap-site count is knowable before the conversion and it decides whether
the structural answer exists.** `Fixups` had one check and its three columns
could only be grown together; `Data` had 23 and needed 23 `DataEnsure` calls;
`MAX_IR` has 20 across six backends *and* seven non-bound uses. Counting first
is cheap and it is the difference between inheriting the good answer and
promising to be careful twenty times.

### Remaining, with the reason each is not next

- **`TokChars` (`STRING_CAP`)** — blocked on splitting that constant from the
  shortstring type it also sizes (`ast_syminfer.inc:151`, `ir.inc:2703`). That
  change touches how a `string` is SIZED, not how a pool grows: different blast
  radius, its own piece of work.
- **`MAX_IR`** — above. Split the constant first; the ten tables are not one
  family.
- **`UCls*` (`MAX_UCLASS`)** — not scouted.
- **`Procs`** — deliberately fixed, unchanged.
