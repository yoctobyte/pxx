---
prio: 28  # auto
---

# c-testsuite 00129: goto past declarations + pathological `s` shadowing + #define s s

- **Type:** bug (cparser scoping/labels). Track C. Low priority (pathological).
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00129: struct tag `s`, member `s`, global `s2`, `#define s s` + `#undef s`,
  `goto s;` jumping over `struct s s;` declaration into a label named `s`.
  Error "pascal26:23: error: expected C expression". Tests that tag / member /
  object / label namespaces are fully separate and goto may skip declarations.

## Gate
Drop 00129.c from test/c-conformance/pxx.skip; runner green.

## Update 2026-07-07
Status: the COMPILER itself SIGSEGVs while compiling 00129 (pathological `#define s s` + `struct s s` var + goto over decls into a label `s:`). It no longer errors cleanly — it crashes. Low priority (prio 28, pathological); a compiler crash on adversarial input, needs a focused debug (likely the `s` name colliding across the tag/member/object/label namespaces + the goto-over-declaration jump). 

## Log
- 2026-07-08 — resolved, commit 2572fc82.
