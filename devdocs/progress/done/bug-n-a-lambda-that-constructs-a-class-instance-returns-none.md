---
type: bug
track: N
prio: 60
status: done
slug: bug-n-a-lambda-that-constructs-a-class-instance-returns-none
summary: "`f = lambda: A(4)` then `f().n` raises AttributeError: 'NoneType' object has no attribute 'n'. The lambda's value is None whenever its body constructs a user class instance, whether it is called directly or through a parameter. The same body in a def works, and so does a lambda returning an int. Found 2026-10-02 (frankuser) at 53dbb01c15, pin v452."
---
# A lambda that constructs a class instance returns None

Found while writing a leak probe that passed `lambda: Sel(4)` to a helper.
It is a wrong value, not a leak, and nothing refuses it at compile time.

## Repro

    class A:
        def __init__(self, n):
            self.n = n

    def mkA():
        return A(6)

    def run(mk):
        o = mk()
        print(o.n)

    f = lambda: A(4)
    print(f().n)        # CPython 4;  pxx: AttributeError, rc=217
    run(mkA)            # 6 on both: a DEF returning the instance is fine
    g = lambda: 7
    run2 = lambda h: h()
    print(run2(g))      # 7 on both: a lambda returning an int is fine
    run(f)              # CPython 4;  pxx: same AttributeError

Built with `./compiler/pascal26 -Fulib/rtl`. The first `f().n` already fails,
so the parameter call is not what loses the value.

## What is established and what is not

- Established: the lambda's result is None (tag None) when its body is a class
  construction. Direct call and call through a parameter both fail.
- Established: a def with the same body works, and so does a lambda whose body
  is an int.
- NOT established: whether the lambda's body is lowered at all, or whether the
  construction runs and its result is dropped on the way out (a Variant-boxing
  arm that does not know tyClass?). Read the lambda's return lowering first.
  An objtrace (`-dPXX_OBJTRACE`) of `f()` shows whether an A is allocated.

## Why prio 60

A silent wrong value on an ordinary Python idiom (`key=lambda: Cls(...)`,
factories, callbacks). It fails loudly at the first attribute access, so it is
not silent corruption, which is why it is not higher.

## Closed (2026-10-02, frankuser)

The construction runs, and the lambda dropped its value. PyCompileLambdaBody
wraps the body in AN_EXIT only when a class-typed value is known to be owned
(`PyLambdaResultIsOwnedTemp`). Otherwise it evaluates the value for its side
effect, a guard against `lambda s: log.append(s)` releasing a captured alias.
A construction is an AN_CALL whose ival is the GetMem intrinsic
(`-Ord(tkGetMem)`, -45) with a user class's record id in ASTRight. The
predicate only knew real proc indices, so a construction was never "owned".
Found with a debug line on the node: `kind=8 tk=6 ival=-45 owned=FALSE`.

Fix (final form, same day): the freshness gate was removed altogether, not
widened. Accepting a construction showed that the same gate returned None for
a captured name, a field, a subscript, `a + b` and a slice. The aliasing
over-release it was built against no longer reproduces: `log.append` and a
method returning `self` run 2000 passes clean under -dPXX_HEAP_DEBUG and the
census is flat. See
bug-n-a-lambda-returning-a-captured-heap-value-yields-none.

Verified against CPython: a direct call, a call through a parameter, a
captured argument, map(), a list of factories, a discarded call, and a kept
instance that is then mutated. Output matches on x86-64, i386, arm32,
aarch64, riscv32 and xtensa. Under -dPXX_HEAP_DEBUG output is identical (no
double release). Census over 5000 passes: live=22 (bound 300); the `keep`
control is live=4709.

Fixture: `test/test_nilpy_a_lambda_that_constructs_a_class_instance_returns_it.npy`.
