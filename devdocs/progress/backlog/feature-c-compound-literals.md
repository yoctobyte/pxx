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
