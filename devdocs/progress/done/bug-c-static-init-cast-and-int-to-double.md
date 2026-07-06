---
prio: 90  # auto
---

# C static initializers: cast-expression and int→double conversion silently produce 0

- **Type:** bug (miscompile — silent zero). Track C.
- **Priority:** HIGH — tiny repros, silent wrong data.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00107 (8 lines): `typedef int myint; myint x = (myint)1;` → x is 0 (main returns x-1 = -1 → exit 255)
- 00119 (7 lines): `double x = 100;` → x is 0.0 (`return x < 1;` exits 1)

## Symptom
File-scope initializer with (a) a cast around a constant, or (b) an integer
literal initializing a double, emits 0 instead of the value. Const-expr
evaluator in the global-init path doesn't fold casts and doesn't convert
int literal → double bits.

## Fix site
cparser.inc global var init const-expr evaluation.

## Gate
Drop 00107.c/00119.c from test/c-conformance/pxx.skip; runner green.

## Log
- 2026-07-07 — resolved, commit 5ba2f898.
