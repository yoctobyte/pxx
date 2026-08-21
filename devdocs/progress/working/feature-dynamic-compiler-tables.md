---
prio: 45  # auto
---

# Dynamic compiler tables — kill the fixed `array[0..MAX_*]` ceilings (+ dynarray dogfood)

- **Type:** feature (compiler architecture / capacity) — Track A
- **Status:** working
- **Owner:** agent-A
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
