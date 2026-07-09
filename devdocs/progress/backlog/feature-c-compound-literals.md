---
prio: 53  # auto
---

# C compound literals `(struct S){...}` — file scope SIGSEGVs, init battery fails

- **Type:** feature/bug. Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00149: `struct S *s = &(struct S){ 1, 2 };` at file scope — exit 139 (SIGSEGV)
- 00150: nested file-scope compound literal with designators — exit 139
- 00216: init battery — empty structs (`typedef struct {} empty_s;`), `(empty_s){}`
  compound-literal member init, `022` octal in init. Compile error
  "expected C expression". (Also overlaps bug-c-init-designated-and-nested.)

## Needed
C99 6.5.2.5: compound literal = anonymous object; at file scope static storage
duration (address is a link-time constant), at block scope automatic. Parser
accepts something today (149/150 COMPILE then crash) — likely treated as cast
of brace list producing garbage pointer.

## Gate
Drop 00149.c/00150.c/00216.c from test/c-conformance/pxx.skip; runner green.

## Triage 2026-07-07
Not implemented in any position: `(struct S){1,2}` as a local/inline expression
-> CERR "expected C expression" (parsed as a cast, then the `{` derails); the
file-scope `&(struct S){...}` parses but SIGSEGVs. Needs: (1) ParseCPrimary/cast
path to disambiguate `(type){...}` (compound literal) from `(type)expr` (cast);
(2) materialize an anonymous object — static storage at file scope, automatic at
block scope — initialize it (reuse the braced-init machinery), and yield its
value / address. Multi-part feature, focused session.

## Parser hook located 2026-07-08 (a-agent) — the reuse blocker
The disambiguation point is `ParseCUnary`'s cast branch (cparser.inc ~1447):
after `if (CurTok.Kind = tkLParen) and CIsCastAhead` parses `castTk := ParseCDeclType`
and `Expect(tkRParen)`, a following `CurTok.Kind = tkBegin` (`{`) means COMPOUND
LITERAL, not a cast — today it falls into `ParseCUnary()` which sees `{` and
derails. Add: `if CurTok.Kind = tkBegin then <materialize + init + yield lvalue>`.

The real blocker is REUSE: the brace-init machinery (record field init, array
element init, nested braces, zero-fill tail) lives INLINE inside
`ParseCLocalDeclAST` (~2760-2920) and `ParseCGlobalVarDecl`, not as a callable
"init this lvalue/symbol from the brace list at TokPos" helper. A clean compound-
literal impl wants that factored out first (a `CParseBraceInitInto(symIdx, tk,
recId)` returning an init AST), then:
- block scope: alloc a hidden local of castTk, CParseBraceInitInto it, yield an
  AN_IDENT lvalue (so `&(T){..}` and `(T){..}.f` work).
- file scope (00149/00150): alloc a static/global anon object, same init, yield
  its address as a link-time constant.
So the sequencing is: (1) extract the brace-init helper, (2) wire the two
compound-literal sites. Step 1 is the bulk and de-risks designated-init too
([[feature-c-designated-init-compound-literals]]). Focused session.

## Progress 2026-07-08 (a-agent) — 00149 + 00150 FIXED (file-scope), 00216 remains
File-scope `T *p = &(RecType){...}` implemented in ParseCGlobalVarDecl: a new
`&(...)` branch materialises an anonymous static record object (name keyed by the
brace token position so both driver passes dedup to one object), initialises it
via the existing deferred aggregate walker (CAggInit / CEmitDeferredCAggInits —
same path a named `struct S g = {...}` global uses, so positional AND nested
designated bodies work), then binds p to its address (PendingInit Elem=-2
address-of-sym). 00149 (positional) and 00150 (nested designated `{.b=2,.a=1}`,
`&gs1`, array member `{[0]=1,1+1}`) both GREEN. Self-host byte-identical, quick
tier green, conformance 208 pass / 0 fail / 12 skip (was 206). Dropped 00149/00150
from pxx.skip.

**Remaining (ticket stays open):**
- 00216 — full init battery: `[a ... b]` range designators, flex-array members,
  unnamed struct/union members (`-fms-extensions`), fn-ptr reloc tables. Overlaps
  [[bug-c-init-designated-and-nested]]. Errors before reaching the CL work
  ("stray token at top level: sys_ni") — parse-level, not the CL path.
- BLOCK-SCOPE compound literals `(T){...}` as an inline expression (the ParseCUnary
  cast-branch hook, ~1447) — still unimplemented; needed for tcc/zlib-style code,
  no conformance test isolates it yet.

## 2026-07-09 (A+B+C agent) — 00216 mapped to 5 sub-features across 4 init paths; range designators LANDED

Retested 00216 at HEAD (v179). It is NOT one gap — it needs 5 distinct
sub-features, spread over 4 SEPARATE initializer code paths, each self-host-
critical. Precise map (minimal repros each confirmed):

1. **Range designators `[lo ... hi] = v`** — the recursive aggregate-init walker
   (`CInitWalkArray`, the `[` designator branch). **DONE this session**: expands
   the range, re-seeking the one value's tokens per index; covers local + global
   struct-member arrays (both route through the walker via CEmitDeferredCAggInits).
   gcc-verified, test/crange_designator_b210.c → exit 42. Overlapping ranges
   resolve left-to-right.
2. **Range designators in the GLOBAL SCALAR-array path** — a DIFFERENT loop
   (`ParseCGlobalVarDecl` ~5352) gated by `CBraceFlatIntInitCountAt`, which rejects
   `[lo...hi]` (only `[int]`). `int g[4]={[0...2]=7}` silently zero-fills. TODO:
   accept the range in the flat-int scanner + the emit loop.
3. **Global FUNCTION-POINTER arrays** `const fptr t[3]={a,b}` — don't parse at all
   ("stray token"): the global pointer-array scanner marks proc names arrKind=3 but
   the emit loop (~5287) has no arrKind=3 case (falls to NULL/int), AND typedef'd
   fn-ptr arrays (`fptr t[N]`) may not reach that scanner. TODO: emit arrKind=3 as
   a proc-address PendingInit (FOff=-4 style) + range support here for the
   `[0...2]=&sys_ni` reloc table.
4. **Nested designators `.a.j = v`** — walker (`CInitWalkRecord` ~4649) handles ONE
   `.name` level then positional; a continuation `.j`/`[i]` in an UNBRACED sub-agg
   isn't processed (designator handling is gated on `braced`). TODO: decouple
   designator-processing from brace-bounding, navigate the full chain pushing path
   frames. (`struct SEB b={.a.j=5}`.)
5. **Inline compound literals `(T){...}` as expressions** — `ParseCUnary` cast
   branch (~1719): after `castTk=ParseCDeclType; Expect(')')`, a following `{` is a
   compound literal, today it recurses into ParseCUnary and derails. The blocker is
   REUSE: materialize an anonymous object (automatic at block scope, static at file
   scope), init it via the brace machinery, yield an lvalue — needs the local
   brace-init extracted into a callable `CParseBraceInitInto`. Self-host-fragile
   (shared init walker). Once this lands, the walker's EMIT-mode leaf (which uses
   ParseCExpr) gets compound-literal VALUES + `&func` + casts for free, unblocking
   `{((struct Wrap){inc}), inc}` and `.a=(struct A){1,2}`.

Order to finish: (2)+(3) global paths, (4) nested designators, then (5) compound
literals (biggest + riskiest). (1) is committed. Remaining pieces parked in
backlog — each a focused, self-host-verified change.

## Assessment 2026-07-08 (cfront-agent) — released; remaining work is deep, needs the factor-out
Confirmed the remaining two pieces are NOT bounded wire-ups:
- **Block-scope `(T){...}`**: the file-scope fix reused `CAggInit`/`CEmitDeferredCAggInits`,
  but that is a DEFERRED mechanism — it records (sym, brace-token-pos) and replays the
  init at `main` for globals/statics. A block-scope compound literal must init an
  AUTOMATIC local INLINE at the expression point, which needs the inline local
  brace-init path (`ParseCLocalDeclAST` ~2760-2920) as a callable
  `CParseBraceInitInto(lvalue)` helper. That factor-out is the bulk and is
  self-host-fragile (touches the shared init walker). No conformance test isolates
  block-scope CL yet.
- **00216**: errors at parse level ("stray token at top level: sys_ni") on range
  designators `[a...b]` / flex arrays / unnamed members — belongs with
  [[bug-c-init-designated-and-nested]], not the CL path.
Both want a dedicated focused session (extract the brace-init helper first). Released
back to backlog unclaimed; 00149/00150 stay fixed.
