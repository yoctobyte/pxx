---
prio: 40
owner: frank-optimize
---

# Inline expansion — remaining slices (branch-with-locals + non-leaf)

- **Type:** feature (codegen — optimization) — **Track O** (Optimization lane; file-ownership Track A)
- **Status:** done
- **Opened:** 2026-07-04 (follow-up split from [[feature-inline-routines]])
- **Umbrella:** the `-O2`/`-O3` tier of [[feature-optimization-levels]]; the
  earlier inline slices (v1 pure-expr, 2a if-then-else Result, 2b straight-line
  multi-statement) all **shipped at -O2** — this ticket carries the deferred rest.

## What shipped already (context — do not redo)

`feature-inline-routines` delivered, all at -O2, all gated `OptLevel>=2`,
-O0/-O1 byte-identical, validated O0-vs-O2 across ~700 programs + 4 cross targets:

- **v1** — pure-expression leaf `Result := E`.
- **2a** — `if C then Result:=A else Result:=B` (retained as `AN_TERNARY`).
- **3** — arbitrary arg expressions via eval-order-safe temps.
- **2b** — straight-line multi-statement bodies with scalar ordinal locals + a
  single Result (`t:=a+b; Result:=t*t`). Retained as the whole `AN_SEQ` chain with
  `AN_INLINE_PARAM`/`AN_INLINE_LOCAL`/`AN_INLINE_RESULT` placeholders.

The retention/splice machinery (`TryRetainInlineBody` /
`TryRetainInlineStmtBody` in `parser.inc`; `IRInlineExpand` / `IRCloneInlineBody`
in `ir.inc`; the reserved AST region + placeholders) is the reusable base for
everything below.

## Slice 2c — if-then-else *with* locals / multiple statements per branch

2b is **straight-line only** (rejects any `AN_IF` in a multi-statement body). The
common next shape is a body that branches AND uses locals, e.g.

```pascal
function Clamp(v, lo, hi: Integer): Integer; inline;
begin
  Result := v;
  if Result < lo then Result := lo;
  if Result > hi then Result := hi;
end;
```

Blockers to solve:
- **Branch-aware assigned-before-read.** 2b's read-before-write guard
  (`InlineWrittenLocal`) is a simple linear scan. With branches, a local/Result
  assigned only inside one arm is NOT guaranteed assigned after the `if` — the
  guard must become a conservative dataflow (a var is "assigned after S" only if
  assigned on ALL paths through S). Reject anything it can't prove.
- **Result read is currently forbidden** (v1..2b) to dodge the uninitialised-
  Result hazard. Clamp above READS Result. Options: (a) allow Result-read once a
  prior unconditional assignment is proven (the assigned-before-read analysis
  covers this), or (b) zero-init the Result temp when the body reads it before an
  unconditional write — but that can diverge from -O0's stack-garbage semantics,
  so (a) is preferred.
- Statement cloning already handles `AN_IF` (generic `Left`/`Right` recursion in
  `CloneToInlineRegion`/`IRCloneInlineBody`) — the work is the *analysis*, not the
  splice.

## Slice 4 — non-leaf inlining (under a depth budget)

Drop the leaf-only rule: inline bodies that themselves call. The ~97% of call
sites 2b/2c can't reach. Needs (see the design notes in
[[feature-inline-routines]] "slice 4" section):
- **Depth budget + recursion guard by proc identity** (a stack of procs being
  inlined; skip a proc already on the stack → normal call). Extend
  `InliningActive` from a boolean-ish counter to a real depth + identity stack.
- **A cost model** (body-node count × call-site count under a budget) so non-leaf
  bodies don't blow up code size / I-cache. Static heuristic only — no profile.
- **Early `Exit` → merge label** for bodies with a mid-flow return.
- This is the real FPC-parity lever and the highest-risk slice. **-O3** (opt-in)
  until a cost model proves it doesn't regress.

## Acceptance (per slice)

- `-O0`/`-O1` byte-identical (gate `OptLevel >= tier`); the shipped slice's
  self-fixedpoint byte-identical; `make test-opt` differential green; O0-vs
  broad sweep + cross targets clean; new oracle cases in `test_inline_expand`.
- Slice 4 additionally: a code-size regression check (record -O2/-O3 sizes) so
  the cost model is honest.

## Related

- [[feature-inline-routines]] — the shipped base (v1/2a/2b/3).
- [[feature-optimization-levels]] — umbrella.
- [[feature-callconv-register-args]] — the other -O2 codegen win.

## Log

- 2026-07-18 night (fable-O) **Slice 2c LANDED (-O3): branch-with-locals.**
  `TryRetainInlineStmtBody` now accepts `if C then <assigns> [else <assigns>]`
  statements (arms = single assign or straight-line assign chain) under a
  DEFINITE-assignment dataflow: entry state saved per if; each arm validated
  with reads gated on definite-at-entry ∪ written-earlier-in-arm; merge =
  entry ∪ (then ∩ else); no-else keeps entry. Result-read now allowed
  (`InlineExprSimple` gains `allowResRead`; `InlineResultDef` global) but only
  when definitely written — -O0 stack-garbage Result is never observable
  (ticket option (a)). Result must be definite at body end. Splice side
  untouched (generic clone + IRLowerAST handles AN_IF). 2b straight-line stays
  -O2; branch acceptance gated OptLevel>=3. Nested ifs inside arms decline
  (v1). Known non-firing shape: bare-funcname-as-VALUE bodies (`F := v; if
  F < lo …`) — funcname in expr position is not a Result-read in this dialect;
  call fallback keeps them correct.
  Test `test_inline_branch_locals.pas` (optdiff-swept): guard-if local,
  if/else Result, 3-statement clamp-via-local, mixed entry-definite reads —
  all inline (IR call-site diff O2→O3 = the three 2c shapes; the if/else
  Result one already fires at -O2 via 2a) and outputs identical -O0/-O2/-O3
  + aarch64 O0-vs-O3 under qemu. Gates: test-opt, quick, make bootstrap
  (FPC seed), C 220/220, nilpy, mandelbrot/nbody checksums, O3-built compiler
  byte-identical. Clamp-style microbench -O3 vs -O2: 1.32x.
  REMAINING (this ticket): non-leaf inlining (callee makes calls); nested ifs
  in arms; while/for bodies.

- 2026-07-18 night (fable-O) **2c increment: NESTED ifs in arms.** The if
  save/validate/merge dataflow extracted to `InlineIfValidate`;
  `InlineArmValidate` recurses through it (mutual recursion, forward decl in
  parser.inc — FPC-seed verified via `make bootstrap`). Definite-assignment
  composes: an inner if/else that writes a local on both paths makes it
  definite for the rest of the outer arm. Test extends with `Grade` (nested
  if/else in a then-arm) — 4 call sites now vanish at -O3, outputs identical
  -O0/-O2/-O3 + aarch64 differential. Gates: test-opt, quick, bootstrap,
  O3-built byte-identical, mandelbrot checksum. REMAINING: non-leaf (callee
  makes calls); while/for bodies.

- 2026-07-18 night (fable-O) **NON-LEAF slice 1 LANDED (-O3).**
  `InlineExprSimple` accepts a direct `AN_CALL` to a plain internal scalar
  function (non-extern/cdecl/variadic/generator, arg count checked, args
  recursively simple, plain-call shape only) as an expression element — so
  wrapper bodies (`Wrap := Leaf(a) + Leaf(b)*2`, incl. inside 2b/2c chains and
  arms) now retain. The spliced body's inner calls stay REAL calls
  (InliningActive already blocks re-inlining) — the win is the removed outer
  frame; measured 1.13x on a 3-wrapper loop despite inner leaf-calls
  materializing. Correctness key: `InlineBodyHasCall[proc]` (set via
  `InlineRetentionSawCall` during validation) forces the splice to
  temp-capture EVERY argument — a direct-substituted pure arg's placeholder
  can sit after the inner call's side effects. Side-effect-exact test
  `test_inline_nonleaf.pas` (g= counts the callee's global increments) —
  identical -O0/-O2/-O3 + aarch64 differential. Gates: test-opt, quick,
  bootstrap (FPC), C 220/220, nilpy, checksums, O3-built byte-identical.
  FUTURE: depth-1 re-inline of inner calls inside splices (lift the
  InliningActive=0 gate to a depth budget) — would recover the leaf-in-wrapper
  fusion the -O2 wrapper call keeps today. REMAINING: while/for bodies.

- 2026-07-18 late night (fable-O) **depth-1 re-inline REVERTED** (revert of
  a3f6e70a). A 10-minute pasmith O-level self-differential fuzz run (new
  harness: random programs, -O0 vs -O2 vs -O3 output diff) produced 21
  SILENT -O3 divergences; commit-bisect pinned a3f6e70a (2c/non-leaf commits
  GREEN), and reverting it clears all 21. The InlineResultSym-local fix was
  necessary but not sufficient — some further nesting-state interaction
  diverges values. All curated gates (test-opt corpus, benches, the inline
  tests) had passed — ONLY the random-program fuzz caught it. Repro corpus
  kept in the session scratchpad; a reduced case is being minimized for the
  re-land. LESSON: fuzz before pushing aggressive splice-machinery changes;
  the optdiff corpus is too tame for inliner state bugs. Non-leaf slice 1
  (inner calls stay real) remains landed and fuzz-clean.

- 2026-07-18 late night: post-revert master **fuzz-clean — 1724 pasmith
  programs, 25 min, zero O0/O2/O3 divergences** (tools/optfuzz.sh). The full
  remaining -O3 stack (ABI/residency both arches, regcall p3 both slices,
  inline 2c + nested-ifs + non-leaf slice 1) holds under random programs.
  Depth-1 re-land blocked on the reduced repro's root cause.

- 2026-07-19 early (fable-O) **depth-1 re-inline RE-LANDED, root-caused.**
  The pinned-anchored reducer (oracle: pinned-O3 + bad-O0 + bad-O2 must all
  agree, only bad-O3 diverging counts — REQUIRED, or reduction drifts into
  uninitialized-Result UB) shrank the repro to 88 lines and exposed the true
  bug: `IRInlineExpand` bound arguments into the SHARED `InlineArgAST[]`
  while argument LOWERING can re-enter the expander (a nested call in a
  splice's argument list at depth<2) — the inner activation rebinds the
  outer's argument ASTs mid-loop. Fix = the REENTRANCY CONTRACT: bind into a
  local `boundAST[]`, publish the Inline* globals only inside the clone
  window (IRClone* never lowers → no reentry), hold the Result temp in a
  local across the reentrant body lowering. Bonus: arg capture now runs
  OUTSIDE the depth bump, so argument calls inline at current depth.
  New regression `test_inline_depth_reentry.pas` — PROVEN to catch the
  reverted binary (diverges on it) and identical on the fix at -O0/-O2/-O3 +
  aarch64. Pre-land fuzz: **1216 programs, 0 diffs**; full battery green
  (test-opt, quick, bootstrap, benches, O3-built byte-identical). Side-find
  from the UB-drifting reducer already filed:
  [[bug-pascal-undefined-field-on-empty-record-compiles]].

- 2026-07-19 (sweep) **PARKED to backlog.** Shipped this campaign: 2c
  branch-with-locals (8f144dfe) + nested-ifs-in-arms (17a2f1e5), non-leaf
  slice 1 (7711208e), depth-1 re-inline reverted (819cb25a, 21 fuzz
  divergences) then root-caused + re-landed with the IRInlineExpand reentrancy
  contract (d4c19919); post-land fuzz-clean. REMAINING scope for the next
  session: while/for loop bodies; deeper non-leaf (depth budget >1).

## 2026-09-05 (frank-optimize) — the depth budget lifted; the REACH is the finding

Two slices remained: while/for bodies, and depth>1 non-leaf. **Measured the
bound on each before writing any code**, because the choice between them is an
empirical question and the census-of-opportunity answer would have been wrong.

| remaining slice | current -O3 | hand-inlined | bound |
| --- | --- | --- | --- |
| while/for body (`SumTo(3)` in a hot loop) | 0.26s | 0.19s | 1.37x |
| **depth>1 non-leaf** (Top -> Mid -> Leaf) | 0.53s | 0.17s | **3.12x** |

`SumTo` declines today (`PXXDBG=a.inline` shows no retention), confirming the
loop-body slice is unimplemented rather than merely unprofitable.

**Isolated the mechanism instead of inferring it.** Hand-inlining ONLY `Leaf`
into `Mid` — leaving the `Top`->`Mid` chain to the compiler — gave 0.16s against
0.46s. So one additional depth level is worth 2.87x of the 3.29x total, and the
budget is the cost rather than anything else in the pass.

### The change

`InliningActive < 2` in the `AN_CALL` gate was a bare literal permitting one
re-inline level. It is now `MAX_INLINE_DEPTH` (defs.inc) = 3. **The constant is
the termination proof, not a tuning knob**: there is no recursion guard by proc
identity, so a self-recursive chain stops only because the budget is spent.
`RecSum` in the new test exists to keep that honest.

### Delivered, and the reach is narrow

- 3-level wrapper loop: 0.46s -> 0.24s = **1.92x** (bound 3.29x, so 69% captured;
  the splice does not reach the 0.16s a human gets, because it carries temps)
- **raytracer 768x512: 2.08s -> 1.84s = 1.13x**, identical checksum, **+8192
  bytes (+5.4%)**
- **12 of 13 real example programs: byte-identical output. Zero change.**
- `compiler.pas`: byte-identical at -O0/-O1/-O2 **and -O3**

**EVERY NUMBER IN THIS SECTION WAS TAKEN UNDER LOAD 12.9-15.2** (fleet gating;
frankC, frankS and frankH all building). That is the contaminated regime, not the
clean one, and this ticket's own calibration pair from the record half says which
way it errs: the same kind of ratio read 1.543x unloaded and 1.665x at load
16-19, ~8% inflated, because the call-heavy control loses more to contention than
the inlined arm does. **So 1.92x and 1.13x are upper estimates and both need a
re-take on a quiet box before they are quoted as delivered.** Recording them with
their conditions rather than discarding them: the pair above is enough to
calibrate, and the byte-identical results (12 of 13 programs, compiler.pas at
every level) are load-INDEPENDENT and stand as measured.

**The 12-of-13 is the honest headline, not the 1.92x.** The extra level needs a
three-deep chain of mutually-retained bodies, and that conjunction is rare: 170
procs retain in `compiler.pas` and 60 of those have calls, yet the depth change
alters nothing there. Checked `FrameIntrinsicUsed` first as the candidate
explanation and it is NOT the cause — no frame intrinsic is called in
`compiler.pas` (the grep hits are the parser recognising the names).

So this is a **narrow win at an opt-in level**, not a general one. It is
recorded that way so nobody reads 1.92x as what a program will get.

### Not proven

`test_inline_depth2.pas` added and wired into the -O3 sweep block. Its expected
values are **FPC 3.2.2's** (verified by compiling and running it under FPC), per
that block's own standard. It asserts side-effect COUNT and ORDER through two
splice levels, not values alone — a value check cannot see an argument evaluated
twice when the second evaluation yields the same number. Confirmed the test is
AIMED: the emitted binary differs between the old and new compilers, so its
program actually reaches the new path.

Also corrected `test_inline_nonleaf.pas`'s header, which still claimed inner
calls stay real calls — untrue since d4c19919 re-landed depth-1.

**REMAINING: while/for loop bodies (bound 1.37x, measured above).**

## 2026-09-05 — REACH measured before implementing the while/for slice

The depth slice was chosen on the bigger BOUND (3.12x vs 1.37x) and delivered
the smaller result: 12 of 13 real programs byte-identical. That is the
measurement establishing the principle, so the remaining slice gets its reach
counted FIRST, before any code.

Added `PXXDBG=a.inlinedecline` (inert unless enabled; `compiler.pas` byte-
identical at -O0/-O2/-O3 with and without it): which statement kind stopped a
body that had ALREADY cleared the locals and Result gates.

Across 13 example programs + `compiler.pas` — **distinct function names**, because
the RTL is recompiled into every program and inflates a raw count (`StrLCopy`
appears 24 times, `StrLComp` and `StrIComp` 12 each):

| blocking statement | distinct functions |
| --- | --- |
| `while` | 102 |
| **bare call statement (`AN_CALL`)** | **67** |
| `for` | 32 |
| `case` | 19 |
| `repeat` / `asm` | 1 each |

**135 distinct functions are blocked solely by a loop statement**, against the
depth slice's one affected program in thirteen. Reach favours while/for by two
orders of magnitude even though its ceiling is less than half.

**135 IS AN UPPER BOUND AND PROBABLY A LOOSE ONE.** These bodies cleared the
locals/Result gates and hit a loop; accepting loops does not make them inline.
The binding constraint will be definite assignment: `for i := 1 to n do Result
:= ...` does NOT definitely assign Result, because the loop may run zero times,
and the same applies to every `while`. How much of the 135 survives that cannot
be known without implementing the analysis, so this number sizes the OPPORTUNITY
and must not be quoted as delivery — the distinction this ticket already got
wrong once.

**A measurement fault worth recording, caught by frank-coordinator's caution that
zero and unmeasurable must not both print 0:** the first census printed
`life 2`. `life` does not compile here at all (rc=1, no binary — the GTK3 headers
resolve to GTK2; identical on all three compilers, so not a regression), and the
2 was partial output emitted before the error. The re-run guards on rc AND on the
binary existing, and prints `UNMEASURABLE`. `sudoku`'s 0 is genuine — it compiles
and has no declines at all. The depth census in the section above was NOT
affected: it guarded compiles with `|| continue`, `life` is absent from its
thirteen, and `built=13` is consistent with that.

### A shape no ticket names

**67 distinct functions decline on a bare procedure-call statement in the body**
— the second-largest blocker, larger than `for`, and not in this ticket's
remaining scope nor anywhere else. Filed as
[[feature-opt-inline-bodies-with-a-statement-level-call]].

## 2026-09-05 — CALL-SITE FREQUENCY MEASURED. The admission axis is saturated.

I wrote that nobody should pick another slice by a static metric before someone
measured call-site frequency. That measurement was available the whole time and
neither I nor the coordinator looked: `perf` is denied here
(`kernel.perf_event_paranoid = 4`), but **`compiler.pas` is FPC-bootstrappable
and FPC supports `-pg`** — the playbook has said so under
*"`perf` being blocked is not 'no profiler'"* for some time. Eleven seconds to
build, and `gprof -b -p` prints call counts that are **properties of the SOURCE
and exactly ours** (the time shares are FPC's codegen and only indicative; the
counts are not).

Workload: the `-pg` compiler compiling `examples/raytracer/raytracer.pas` at -O3.

| | calls | share |
| --- | --- | --- |
| total attributed | 9,507,756 | |
| to functions the inliner **already retains** | 1,235,476 | **13.0%** |
| to functions it **declines on statement kind** | 106,690 | **1.12%** |

**118 of the 156 declined functions are called ZERO times.** Three quarters of
the remaining "opportunity" is code that does not execute at all in a real
compile.

And the 1.12% is concentrated, not spread:

    TYPESLOTSIZE          case    39,995
    RESIDENTREGOF         for     38,847
    BUILTINRECFIELDCOUNT  case     6,053
    FLOATRESIDENTXMMOF    for      4,283
    DCENEWOFF             while    3,277

The top two are 79k of the 107k — **0.4% of all calls each.**

### What this decides

**Admitting every remaining statement shape would touch ~1% of executed calls**,
and inlining does not make a call free, so the realisable gain is a fraction of
that. The inliner already covers the functions taking 13% of calls. **The axis is
saturated and the remaining slices are not worth their risk** — this ticket's own
history is a revert after 21 silent divergences, which is the price of being
wrong in this machinery.

**This retires all three static metrics, mine included.** Bound picked depth>1
(changed 1 program of 13). Reach picked statement-calls (changed 0 of 16).
Frequency now says why both failed: they counted shapes a validator could admit,
and the shapes it cannot admit are overwhelmingly **cold**.

**THE AXIS WAS NEVER BOUND-VS-REACH. IT IS STATIC-VS-EXECUTED, and both of my
earlier positions were on the wrong side of it.** I corrected myself once, from
"biggest bound" to "biggest reach", and that correction was still a static metric
and still wrong. Stated this way because the failure mode is picking a FOURTH
static metric — most-call-sites-in-source, most-lines, most-parameters — and
finding it also predicts nothing. A count of source shapes cannot predict
delivered value no matter how the count is refined. **The only metric that
predicted anything was a count of what actually ran.**

**If anyone does pursue this, the answer is not "support `case` and `for`" — it
is `TypeSlotSize` and `ResidentRegOf` specifically**, two functions worth 0.4%
of calls each, and the honest first question is whether either is better served
by not being a function call at all.

**REMAINING SCOPE OF THIS TICKET IS THEREFORE CLOSED ON VALUE, NOT ON DIFFICULTY.**
while/for bodies remain unimplemented and that is now a deliberate decision with
a number behind it rather than an unfinished task.
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
