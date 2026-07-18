---
prio: 45  # auto
---

# Inline expansion — remaining slices (branch-with-locals + non-leaf)

- **Type:** feature (codegen — optimization) — **Track O** (Optimization lane; file-ownership Track A)
- **Status:** working
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
