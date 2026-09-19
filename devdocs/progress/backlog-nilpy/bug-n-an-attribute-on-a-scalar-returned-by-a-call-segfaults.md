---
type: bug
track: N
prio: 70
status: open
slug: bug-n-an-attribute-on-a-scalar-returned-by-a-call-segfaults
owner: frankD
---

# A missing attribute on a scalar returned by a CALL segfaults instead of raising

`mk().foo` where `mk()` returns an int SEGFAULTS. The same access on a bare
identifier holding the same value raises AttributeError correctly, as of
bug-n-an-attribute-on-a-scalar-receiver-answers-the-receiver-instead-of-raising.
This is the CALL-RECEIVER spelling of that ticket, and it was left open there
deliberately: the fix landed on the route the bare identifier takes and this
route is a different function.

Measured 2026-09-19, CPython as oracle, and reproduced on the PINNED compiler
(`stable_linux_amd64/default/stable_pinned`) as well as at HEAD, so it predates
that fix and is not a regression from it:

| expression          | CPython        | pxx @ HEAD and @ pin |
|---------------------|----------------|----------------------|
| `mk().foo`          | AttributeError | **SIGSEGV (rc 139)** |
| `"ab".upper().foo`  | AttributeError | **SIGSEGV (rc 139)** |
| `(5).foo`           | AttributeError | compile: `expected ')' before '.'` |
| `i.foo` (bare name) | AttributeError | AttributeError — FIXED |
| `xs[0].foo`         | AttributeError | AttributeError — was already right |
| `mkd()["k"].foo`    | AttributeError | AttributeError — was already right |

The two correct subscript rows are the control: they prove the receiver being
COMPUTED is not what breaks it. What breaks it is the receiver being a scalar
reached through the chained-selector parser.

## WHY THE OBVIOUS FIX DOES NOT WORK, MEASURED

`PyParseClassRecordSelectors` (pyparser.inc) is the chained-selector loop and is
the natural home for the guard. A guard was written there, at the same position
its sibling occupies in `PyParseLValueAST`, and **a `WriteLn` probe on it fired
ZERO times for every one of the six rows above**, including both segfaulting
ones. It was removed rather than landed: a guard that cannot fire is not a
guard, and it would have read as coverage this shape does not have.

So the first job here is NOT to write a guard — it is to find which arm actually
consumes `.foo` on a call-typed scalar receiver. The differential that located
the bare-identifier site will locate this one too: tag every
`AllocNode(AN_FIELD)` with a `WriteLn` carrying its own line number, compile a
subject WITH the access and one WITHOUT, and diff the tag counts. That named
`PyParseLValueAST` in one run with no reading at all.

## `(5).foo` IS A THIRD THING AND IS NOT THIS TICKET

A parenthesised literal receiver does not parse: `expected ')' before '.'`, on
HEAD and on the pin. CPython accepts it. Loud, not silent, and it has no wrong
value — file separately if it is worth anything.

## Repro

    def mk():
        return 5
    print(mk().foo)

Expect `AttributeError: 'int' object has no attribute 'foo'`; get SIGSEGV.
