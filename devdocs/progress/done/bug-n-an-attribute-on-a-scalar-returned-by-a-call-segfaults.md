---
type: bug
track: N
prio: 70
status: done
slug: bug-n-an-attribute-on-a-scalar-returned-by-a-call-segfaults
owner: frankh-c0
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

## FIXED 2026-09-21 — the predicate asked "is it a VARIANT" where both comments said "is it a CLASS"

### The ticket's own next step was the right one and the instrument was cheaper than it looked

It said the first job is to find which arm consumes `.foo` on a call-typed
scalar receiver, and prescribed tagging every `AllocNode(AN_FIELD)`. **No
`AN_FIELD` is involved**, which is why the `PyParseClassRecordSelectors` probe
fired zero times — `PXXDBG=a.ast` on the failing def answers in one command:

    #8205 kind=8(AN_CALL) tk=22 ival=1467
      #8203 AN_ARG -> #8201 kind=8(AN_CALL) tk=13   <- mk(), an Int64
                   -> #8202 AN_STR_LIT 'foo'

`.foo` becomes a CALL to a dynamic getter with the receiver as an argument. The
AST dump was the instrument; the AN_FIELD census would have enumerated a
population the subject is not in.

### Root cause, one line

`PyMakeDynAttrGet` (`pyparser.inc`) chose the route with

    isVariantRecv := IntToTypeKind(ASTTk[baseNode]) = tyVariant;

and sent everything else through `PyMakeObjPtr` into `pydynattr_get`, which
dereferences the receiver as an object pointer. **"Not a variant" and "is a
class" are the same question only until a receiver is STATICALLY SCALAR** —
which is exactly what a call result is, because the def's return type is
inferred as `tyInt64`/`tyDouble`/`tyBoolean`/`tyAnsiString` rather than left
dynamic.

**Both routes' own comments named the right rule.** `PyMakeDynAttrGet`'s header
says *"for a receiver STATICALLY known to be a class"*; `pydynattr_get`'s body
says *"NEVER an int/str/etc scalar, so ClassName on a non-nil obj is always safe
here."* Two files, two comments, one contract — and the single predicate that
enforces it tested something else. Comment versus code, and the comments were
right.

### The differential, receiver static kind printed at the deciding line

One subject per file. Before / after:

    receiver kind    subject                before        after
    tyClass    (6)   mkc().foo              AttributeError  unchanged
    tyVariant  (22)  xs[0].foo              AttributeError  unchanged
    tyInt64    (13)  mk().foo   -> 5        SIGSEGV 139     AttributeError
    tyAnsiString(23) mk().foo   -> "ab"     SIGSEGV 139     AttributeError
    tyAnsiString(23) "ab".upper().foo       SIGSEGV 139     AttributeError
    tyDouble   (19)  mk().foo   -> 2.5      SIGSEGV 139     AttributeError
    tyBoolean  (2)   mk().foo   -> True     SIGSEGV 139     AttributeError

**Broader than the ticket recorded**: it listed int and str; float and bool
segfault too, and every one of them is the same predicate.

All nine rows (those eight plus a caught-in-`try` row) are **byte-identical to
CPython**, message and receiver type name included.

### The fix

`useObjRoute := IntToTypeKind(ASTTk[baseNode]) = tyClass;` — the object-pointer
route for a statically class-typed receiver, `pydynattr_get_v` for everything
else, which boxes the scalar and lets the runtime tag decide. That is the
contract both comments already stated.

### Regression argument, and the honest weakness in it

A route census over the NilPy fixture corpus recorded **338 arrivals** at that
line and saw only `tyVariant` (326) and `tyClass` (12) — no third kind — so
narrowing to `tyClass` takes nothing from code that works today.

**Read that as PARTIAL.** I rebuilt the compiler while the census was still
running, so the probe stopped printing partway and it covers an unknown PREFIX
of the corpus. The corruption can only DROP rows, never invent them, so *"no
third kind appeared in 338 arrivals"* stands and *"no third kind exists"* is not
claimed. Recorded rather than glossed because it is this repo's own
do-not-touch-the-instrument rule, and I broke it while holding it. The evidence
that nothing regressed is the NilPy tier, which is an outcome rather than a
proxy.

### The fixture, and its positive control

`test/test_nilpy_an_attribute_on_a_scalar_returned_by_a_call_raises_attributeerror.npy`
— thirteen rows: the four scalar kinds through a call, a method result, the
class and container receivers that already worked (so the scalars cannot be
fixed by breaking them), and three rows where the attribute IS present (so the
file cannot pass against a stub that raises unconditionally). Byte-identical to
CPython.

**Positive control: it SEGFAULTS (rc 139) under pin v416 (`fddc21e7e661`)** and
is byte-identical to CPython at HEAD. The guard can go red, and the compiler
that reds it is one anybody can run.

Every row asserts the **type name in the message**, not merely that something
was raised — a wrong route could raise with the wrong receiver name, and a bare
"AttributeError was raised" row cannot tell those apart.

### Not taken, and named so the next reader does not assume

- **`(5).foo`** still fails to parse (`expected ')' before '.'`). The ticket
  already says it is a third thing; it is loud and has no wrong value.
- **`mk().foo = 1` does not parse either** — a call result is not accepted as an
  assignment target, where CPython accepts it and raises at run time. Found
  while checking the setter; loud, not silent, and not this ticket.
- **THE SETTER SIBLING IS A REAL BUG AND IT IS SEPARATE**: `xs[0].foo = 1`
  SEGFAULTS (rc 139) where CPython raises. `pydynattr_set_v`'s own comment says
  *"Only a CLASS REFERENCE needs telling apart here"*, and a scalar-tagged
  variant falls straight through to `pydynattr_set(pyvarobj(v), ...)`, which
  reinterprets scalar bits as an address. **Its twin `pydynattr_get_v` checks
  the tag and says in its comment exactly why** — so one concept, two runtimes,
  written with different beliefs about the same population. Carried to its own
  ticket rather than folded in, because it is a `compiler/builtin/**` change and
  wants its own verification.

## Log
- 2026-09-22 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
