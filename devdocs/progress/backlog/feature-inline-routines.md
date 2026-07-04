# Inline routine expansion (`inline;`)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (design discussion — small-helper performance)

## Motivation

`inline;` is currently parsed and **accepted as a no-op** (see
[dialect/routines.md](../../dialect/routines.md)). PXX is single-pass with no
optimisation passes, so a call to a tiny helper pays full overhead:
prologue + epilogue + argument shuffle + `call` + `ret`. For small math/boolean
helpers (`Min`/`Max`/`Clamp`, bit twiddles, vector component ops) that overhead
dwarfs the actual work — often a 3-instruction body behind a ~5× call cost.
Honouring `inline;` for these is a real, broad performance win, especially in
hot loops and on embedded targets where every cycle counts.

## Approach — blunt and strict, at the IR level

Inline only `inline;`-marked routines that are clearly safe; otherwise emit a
normal call. **Never** silently miscompile and **never** hard-fail on an
ineligible body — degrade to a call and (optionally) warn.

- **Eligibility (v1):** free function/procedure (not a method first), single
  `Result` / no multiple exits, parameters and locals that are
  ordinal/pointer/float, **no managed locals/params** (string / dynarray /
  record with managed fields), **not recursive** (direct or mutual), body under
  a size cap.
- **Mechanism:** at IR construction/lowering, splice the callee IR into the call
  site — bind each argument to a fresh temp (evaluate once, preserve
  left-to-right order and side effects), rename callee locals to fresh slots,
  redirect `Result` to a caller temp, and translate the callee's single exit to
  a fall-through.
- **Ineligible →** compiler **warning** (`inline ignored: <reason>`) + normal
  call. Gate the warning so it is informative, not noise.

## Expectation setting

Without a constant-folding / peephole pass, inlining mainly removes call
overhead (no cross-boundary folding yet). That is still a large relative win on
tiny hot helpers. If a folding pass lands later, inline compounds with it.

## Scope boundaries (later slices)

- Methods / `Self` handling.
- Inlining routines that themselves call (non-leaf) under a depth budget.
- Inlining across units.
- A cost model / auto-inline of trivial routines even without the directive.

## Acceptance

- An `inline;`-marked eligible leaf helper emits **no `call`** at its use sites;
  the body is spliced with correct argument evaluation order and `Result`.
- An ineligible `inline;` routine compiles (warning + normal call), output
  unchanged vs. today.
- New oracle test exercising arg side-effect order, nested inline calls in one
  expression, and an ineligible case; `make test` green; `make cross-bootstrap`
  byte-identical on i386 + aarch64 + arm32.

## Update — greenlit + auto-inline scope (2026-07-03)

Part of the pin-time optimization campaign (see
[[feature-optimization-levels]], measured 2.04x codegen gap). Additions to
the original design:

- **Auto-inline (-O2)**: beyond honouring explicit `inline;`, auto-select
  candidates at -O2: leaf routines (no calls), body under a small IR-node
  budget (~12 nodes), no address-taken params/locals, not virtual/indirect/
  external/vararg, single return path. Explicit `inline;` keeps working at
  -O1; auto-inline is additive and silent (a `--warn-inline` diag can list
  decisions). The eligibility analysis (leaf/addr-taken/size) is the same
  scaffold [[feature-callconv-register-args]] needs — build it once.
- Self-host gate unchanged: -O0 byte-identical; inlining only under -O1+.

## Phase 0 MEASURED (2026-07-04) — opportunity sized

`--measure-inline` flag added (flag-gated, no codegen change): per compiled body
records IR-node count + leaf/early-exit/addr-taken-param facts; per direct
internal call target counts the call sites (`InlineMeasureBody` /
`InlineMeasureSummary` in ir_codegen.inc).

Measured on the compiler self-compile (30438 total direct call sites), leaf-only,
budget ≤12 IR nodes:

| Eligibility variant | procs | call sites |
|---|---|---|
| strict (single-exit + no addr-taken param) | 19 | 664 |
| relax early-exit | 19 | 664 |
| relax addr-taken | 21 | 670 |
| loose (leaf + size only) | 21 | 670 |

By budget (strict): @6 nodes → 617 sites; @12 → 664; @20 → 757.

Findings:
- **Strict eligibility captures ~99% of the leaf opportunity** (664/670). The
  single-exit and no-addr-taken-param restrictions cost almost nothing here —
  tiny leaf helpers rarely early-Exit or take a param's address. So v1 can be
  strict *and* safe with negligible loss.
- **~664 sites = 2.2% of all direct calls** — bounded, but concentrated on hot
  tiny helpers, each site saving a full call sequence (prologue/epilogue/arg
  shuffle/call/ret ≈ 6–8 instr). Comparable in magnitude to the regcall win
  ([[feature-callconv-register-args]] phase 1).
- The other ~97% of calls target NON-leaf or larger procs → needs depth-budget
  (non-leaf) inlining, a much larger effort. Deferred to a later slice.

Decision: implement v1 = explicit `inline;` + strict leaf auto-inline (-O2),
IR-splice at the call site. Both gated OptLevel>=2 (auto-inline could move to -O3
if we want explicit `inline;` at -O2 and auto at -O3 — user flagged this as an
option). Measure the actual self-compile delta after landing.

## Implementation plan (worked out 2026-07-04) — the single-pass obstacle + the fix

**The obstacle.** PXX is single-pass: each proc's body AST is lowered to machine
code in its own CompileAST, then `ASTNodeCount := 0` (parser.inc ~14826/10044)
frees the AST pool, and the IR is IRReset per body. So at a call site the callee's
body AST/IR **no longer exists**. IR-level splicing (as the original "Approach"
section imagined) is therefore impossible without retaining the callee body.

**The fix — retain eligible inline bodies, copy-in + re-lower at the call site.**

1. **Directive capture.** `inline` is currently a silent no-op modifier
   (parser.inc ~13544-13570, just `Next; Eat(semicolon)`). Add `ProcInline:
   array[0..MAX_PROCS-1] of Boolean` (defs.inc) and set it there. Auto-inline
   (-O2) additionally treats any proc passing the eligibility test as inline even
   without the directive.

2. **Retain the body in a dedicated pool.** New `InlAST*` arrays (parallel to
   ASTKind/ASTLeft/ASTRight/ASTIVal/ASTTk, a few thousand entries — inline bodies
   are tiny). At the END of parsing an eligible inline proc's body AST (before the
   per-proc reset), **deep-copy its body subtree into InlAST**, remapping child
   indices to InlAST positions. Crucially, rewrite every AN_IDENT that references
   **param i** into a placeholder carrying the param *index* (params syms are torn
   down, so index-not-sym), and every reference to the Result sym into a Result
   placeholder. Record `InlineBodyRoot[procIdx]`, `InlineParamCount[procIdx]`,
   and per-param TypeKind. Bail (leave ProcInline effectively off) if the body
   uses anything outside the eligibility envelope.

3. **Eligibility (v1 = STRICT, measured to lose only ~1%):** leaf (no call in
   body), single-exit (no AN_EXIT), no addr-taken param, params + Result scalar
   int/ptr by-value, no managed/float/record/set/array params or locals, body
   `<= 12` cloned AST nodes, not recursive (proc never inlines itself — guard a
   self-reference), not virtual/external/cdecl/variadic/generator/stackless/
   method. (Direct IR_CALL targets are already non-virtual, so call sites only
   ever hit non-virtual procs.)

4. **Splice at the call site.** In IRLowerAST `AN_CALL` (ir.inc ~3839), FIRST
   thing: if OptLevel>=2 and ProcInline[cpi] and InlineBodyRoot[cpi]>=0 and not
   currently inlining cpi (recursion/nesting guard):
   - For each arg, alloc a fresh caller local temp of the param's type, lower the
     arg into it via the normal path (evaluate once, left-to-right, side effects
     preserved), OR — for a side-effect-free arg (AN_INT_LIT / plain AN_IDENT) —
     bind directly to skip the temp.
   - **Copy the retained InlAST body into the live AST pool** (append at
     ASTNodeCount), remapping InlAST child indices to the new live indices, and
     replacing each param-index placeholder with an AN_IDENT of that param's arg
     temp, and the Result placeholder with a fresh caller Result temp.
   - Lower the copied-in expression normally; the call's IR value = the Result
     temp (for a pure-expression body, = the lowered expression directly).
   - A small `InlineDepth` counter / `InlineActiveProc` stack guards nested and
     self inlining (cap depth 1 in v1; a call *inside* an inline body just emits
     a normal call since eligible bodies are leaf anyway).

5. **v1 body shape = pure expression** (`begin Result := E end`, no locals, no
   control flow): the copy-in reduces to cloning E with param placeholders →
   arg-temp idents; the call value is the lowered E. This is the smallest
   complete slice and covers Sqr/Lo/Hi/bit-twiddle one-liners. Slice 2 adds
   if-then-else Result bodies and simple ordinal locals (fresh caller locals per
   callee local, same placeholder→remap trick, Exit→already-single so
   fall-through). Measured: pure-expr is a subset of the 664 strict sites; slice 2
   reaches most of them.

6. **Gates.** Everything gated OptLevel>=2 → -O0/-O1 byte-identical untouched.
   New gate in test-opt: an -O2 differential test with an `inline;` helper whose
   arg has a side effect (called twice in one expression) must match -O0 output;
   -O2 self-fixedpoint stays byte-identical; make test green. Add an oracle test
   (arg side-effect order, nested inline in one expression, an ineligible case
   that degrades to a call with a `--warn-inline` note).

**Effort:** ~150-200 lines, self-contained (defs.inc arrays + parser retain hook +
ir.inc AN_CALL splice + AN_IDENT placeholder handling). The eligibility scaffold
(leaf/addr-taken/size) already exists from `--measure-inline`
([[feature-callconv-register-args]] shares it). Risk is the AST copy-in remap
(off-by-one on child indices) — validate with the -O2 self-fixedpoint before
committing, exactly as regcall phase 1 did.

## v1 SHIPPED (2026-07-04) — pure-expression leaf auto-inline (-O2)

Landed exactly per the plan above. A leaf function whose body is a single
`Result := E` over scalar-by-value params (E = int/ordinal literals +
param/global/const idents + arithmetic/logical operators) is retained in the
reserved AST region `[INLINE_AST_BASE..MAX_AST)` with param idents → AN_INLINE_PARAM
placeholders (`TryRetainInlineBody`, parser.inc), and spliced at a direct call
site whose args are all side-effect-free (`IRInlineExpand`/`IRCloneInlineBody`,
ir.inc) — the retained E is cloned into the live pool with placeholders bound to
the arg ASTs, lowered, and its value replaces the call.

- **Auto-inline**: keys on eligibility, not the `inline;` keyword (also captured
  now). All eligible pure-expr leaves inline at -O2. Both explicit and auto at
  -O2 (not the -O1/-O2 split the plan floated — simpler, and -O0/-O1 stay
  byte-identical either way).
- **Args**: v1 requires side-effect-free args (literal / plain scalar ident) →
  direct substitution, no temps, eval order trivially preserved. A complex arg
  (`Sqr(a+b)`) declines → normal call. Nested `Sqr(Sqr(x))` → outer normal call,
  inner inlines.
- Ineligible (locals, control flow, managed/float, non-leaf, method, >6 params,
  non-scalar) degrades to a call. Recursion/nesting guarded (`InliningActive`).
- New AST kind `AN_INLINE_PARAM=78`; `AllocNode` guard moved to `INLINE_AST_BASE`.

Gates: -O0 self-host byte-identical; -O2 self-fixedpoint byte-identical (auto-
inline active on the compiler's own source); make test green; test-opt green with
`test/test_inline_expand.pas` in the -O2 differential corpus (O0==O2 across
arithmetic/boolean/multi-param/nested/loop/const-arg/ineligible cases).

Impact: on the compiler's OWN self-compile the win is marginal (it has few
pure-expr one-liners; a handful of sites fire, code +~20KB from call-site
duplication). The real payoff is user code with hot tiny helpers (Sqr/Min/Max/
bit-twiddles), where each site drops a full call sequence.

## Next slices (measure/scope before building)
- **Slice 2a**: ✅ DONE (2026-07-04). `if C then Result:=A else Result:=B`
  one-liners retained as a synthesized `AN_TERNARY(C?A:B)` (`BuildInlineTernary`,
  parser.inc) — reuses the value-return splice + slice-3 arg temps unchanged;
  AN_TERNARY's short-circuit lowering yields the value. Covers Min/Max/Clamp-
  style helpers. Gates green.
- **Slice 2b**: ✅ DONE (2026-07-04) — **gated -O3** (opt-in until proven, keeps
  the pinned -O2 untouched; -O2 output verified byte-identical to the pin).
  Straight-line multi-statement bodies with scalar ordinal locals + single Result
  (`t:=a+b; Result:=t*t`). Retains the whole AN_SEQ chain with param/local/Result
  → `AN_INLINE_PARAM`/`AN_INLINE_LOCAL`/`AN_INLINE_RESULT` placeholders
  (`TryRetainInlineStmtBody`); at the call site allocs fresh caller locals + a
  Result temp, clones + lowers the statements, returns a load of the Result temp.
  Safety: straight-line only (no branches yet), all locals scalar, Result never
  read, read-before-write guard, slice-3 arg temps. Validated O0==O3 across 500
  programs + all 4 cross targets; -O3 self-fixedpoint; test-opt/-cross gated.
  **Remaining for a future slice 2c:** if-then-else *with* locals (needs the
  branch-aware assigned-before-read analysis); early `Exit` → merge label.
- **Slice 3**: ✅ DONE (2026-07-04). Non-pure args evaluated once into fresh temps
  (`IRInlineExpand`, ir.inc). Pure args (literal / plain scalar ident) still
  substitute directly; if ANY arg is impure, ALL args are temp'd left-to-right so
  Pascal eval order holds (Add(g, Bump)=110, Add(Bump, g)=210 verified). Any arg
  expression can now inline, callee eligibility unchanged. Gates green.
- **Slice 4**: non-leaf inlining under a depth budget — the ~97% of calls v1/2
  can't touch; the real lever toward FPC parity. Much larger.
- Methods / cross-unit.

Status: **phase 0 measured + v1 SHIPPED.** Slices 2-4 backlog.
