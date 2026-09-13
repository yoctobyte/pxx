---
slug: bug-n-a-method-s-non-constant-default-is-none-when-the-call-is-inside-the-class
title: a method's non-constant default is None when the call is written inside the class
summary: >
  FIXED 2026-09-13. A method's non-constant default (`def m(self, n=N)`) lives in
  a hidden global that the call site references by SYMBOL, and the symbol was
  recorded on the Proc only after the WHOLE class body had been parsed -- so a
  call written INSIDE the class baked None into the argument while the identical
  call written outside it was right. The symbol is now DECLARED before the body
  loop and still EVALUATED at the class statement. Evaluating early instead was
  measured RED on a COMPUTED class attribute, and the fixture now carries both
  populations.
track: N
type: bug
prio: 60
owner: frank-user
status: done
---

## The measurement

Pin v408, and HEAD before the fix. `.expected` is CPython's own output for the
same file (`test/test_nilpy_a_method_default_that_is_not_a_literal.npy`).

    class C:
        def m_name(self, n=N):       return n        # N = 30 at module level
        def ask_name(self):          return self.m_name()

    print(c.ask_name())   # CPython 30, pxx None   <- the call is INSIDE the class
    print(c.m_name())     # CPython 30, pxx 30     <- the same call OUTSIDE it

Nine rows move: a module global, a string, a float, a tuple, an expression, a
negation, a callee declared BELOW its caller, and two class attributes. Rows with
a literal default, an explicit argument, the call from outside, and a method of
ANOTHER class called from inside this one already passed and are regression
guards.

Declaration order inside the class made no difference, which is the tell that it
was the PASS and not the lookup.

## The mechanism

`PyEvalMethodDefaults` ran from the STATEMENT LOOP, after `PyParseClass`
returned. Every method body in the class had therefore already been parsed, and a
call site in one of them read what the member pre-pass leaves -- `
ProcParamDefaultSym = -1`, `ProcParamDefaultIsNone = True`, because the pre-pass
parses headers with evaluation OFF -- so `DefaultArgValueNode` took its NilPy
`tyVariant` + IsNone arm and baked `PyMakeNone`.

## The fix, and why it is split in two

`PyEvalMethodDefaults(ci, lo, hi, declareOnly)`:

- **declareOnly**, called from `PyParseClass` BEFORE the body loop: allocate
  `$pdef.<Cls>.<def>.<param>` and record it on the Proc. The expression is not
  touched.
- **the real pass**, unchanged, at the class statement: `PyEvalParamDefault`
  finds that symbol by name and queues the store.

Nothing is parsed twice and nothing is evaluated twice. The name is built by one
helper, `PyParamDefaultGlobalName`, used by both -- two spellings of it would
drift and a declared-but-never-stored global reads as None, which is this bug
again with a different cause.

The declared symbol is **tyVariant**, not the value's own type, because the value
is not known yet and a later retype would leave the already-built ident node at
the in-class call site disagreeing with the symbol. A variant is what an omitted
NilPy parameter is anyway.

A lone STRING default is deliberately not declared early: the call site already
builds the literal from sOff/sLen, so declaring one would reroute working code
through a global for no gain.

## What the first attempt got wrong, and it is the reusable part

The first version moved the WHOLE evaluation before the body loop. Gate quick
green, the new fixture green, a clean pin control -- and the full tier found
`test_nilpy_a_method_default_is_evaluated_in_the_class_body` answering
`computed attr None` against `computed attr 14`.

    class D:
        LIMIT = 7 * 2                  # COMPUTED
        def __init__(self, v=LIMIT): ...

The member pre-pass can only guess a class attribute's type from its tokens, so
it types a computed one's `$clsattr.<C>.<name>` slot **tyVariant**;
`PyEmitClassAttrExpr` RETYPES it to what the initialiser actually produced, and
that runs in the class BODY loop. Read before the body loop, the attribute is
still a variant and the default global is allocated variant-shaped over a slot
that ends up an Int64 -- a type mismatch whose value reads as None. Measured with
a probe on the lookup: `$clsattr.D.LIMIT tk=22` against `$clsattr.E.MARGIN
tk=13` in one program.

**A LITERAL attribute is typed correctly by the pre-pass and so needs no retype.**
The fixture's own positive control for the ordering (`MARGIN = 14`) was a
literal, which is the easier population: it passed on the broken version and
certified it. The fixture now carries a COMPUTED one beside it (`SPAN = 3 * 5`,
rows N and O), and under the rejected version those two rows are the ONLY ones
that fail -- every other row of the same fixture passes. That is measured, not
predicted.

## Verified

- `test_nilpy_a_method_default_that_is_not_a_literal`: 15 rows, `.expected` from
  CPython, MATCH at HEAD. Pin v408 answers None on A-F, I, L and N.
- `test_nilpy_a_method_default_is_evaluated_in_the_class_body` (the 2026-09-10
  fixture this first broke): MATCH.
- `tools/gate.sh quick` GREEN, self-host fixedpoint included.
- full `make test-nilpy`.
