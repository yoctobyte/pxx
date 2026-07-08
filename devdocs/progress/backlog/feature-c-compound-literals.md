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
