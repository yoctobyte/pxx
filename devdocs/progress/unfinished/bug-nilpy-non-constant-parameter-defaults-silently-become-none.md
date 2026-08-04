---
track: N
prio: 70
type: bug
summary: "Every non-constant parameter default silently becomes None on the ordinary call path — `def f(b=[])` gives b=None, and so does `def f(b=w)` for any name w. Only the closure-VALUE path evaluates defaults at def time."
status: working
owner: claude-AN
---

# Non-constant parameter defaults silently become `None`

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping function semantics against the CPython oracle.
- **SILENT.** The parameter is simply None; nothing is reported at compile time
  or at run time until something downstream touches it.

## Measured

```python
def acc(v, bucket=[]):
    bucket.append(v)
    return bucket
print(acc(1))        # CPython [1]      pxx  AttributeError: 'NoneType' has no attribute 'append'
```

```python
def f(b=[]):   return b      # CPython []     pxx None
def f(b={}):   return b      # CPython {}     pxx None
def f(b=()):   return b      # CPython ()     pxx None
w = 7
def f(b=w):    return b      # CPython 7      pxx None
w = [1, 2]
def f(b=w):    return b      # CPython [1, 2] pxx None
```

CONSTANT defaults are fine and unaffected: `b=10`, `b="z"`, `b=True`, `b=None`,
`b=2.0`, `b=-1` all work.

So the rule is: **anything that is not a literal scalar token becomes None.**

## Cause

`PyParamDefaultAt` (pyparser.inc) recognises a fixed set of literal tokens
(`tkInteger`, `tkString`, `tkFloat`, `tkTrue`, `tkFalse`, `tkNil`, and a negated
number). Anything else falls into the final `begin ... end` block, which SKIPS
the expression's token span and leaves the parameter as a None-valued optional.
Its own comment says so, and justifies it for uforth's native-word bodies, which
only ever run through the exec/native stub.

That justification no longer covers what the frontend is used for.

## This is NOT covered by the closure-default fix

`feature-nilpy-closure-default-and-remaining` (in `done/`) records
"Closure-captured parameter defaults: FIXED", re-measured against CPython. That
is true but **narrower than it reads**: the def-time re-parse that implements it
lives in `PyNestedDefClosureValue` (pyparser.inc ~4898), so it only runs when a
nested def is materialised as a closure VALUE. A def that is simply *called*
never goes through it:

```python
def outer():
    w = 7
    def inner(b=w):
        return b
    return inner()      # called directly -> None, not 7
print(outer())
```

So the ordinary path was never fixed, and the "FIXED" note should be read as
"fixed for the closure-value path".

## Shape of the real fix

Python evaluates a default **once, at def time** — which is also what makes the
shared-mutable-default gotcha (`acc(1)` -> `[1]`, `acc(2)` -> `[1, 2]`)
observable. So a fresh-per-call empty container would be the WRONG fix: it gets
the common case right and diverges on the accumulator idiom, trading one silent
divergence for a subtler one.

The honest shape, and it mirrors the `$clsattr` machinery that already exists for
class attributes:

1. for a non-constant default, allocate a hidden global `$pdef.<proc>.<param>`
2. hoist `<global> := <expr>` at the DEF statement, so it is evaluated once, in
   the scope where the def stands
3. record the symbol in a new PARALLEL array beside `ProcParamDefaultVal` —
   **not** a new field on the proc record
   ([[project_tsymbol_field_landmine]] is the same hazard one level up)
4. the omitted-argument fill emits an ident on that global instead of the ordinal

Step 4 is the awkward part: the fill is done at **four** sites in `parser.inc`
(~2594, ~2602, ~2628, ~12381), all on the shared call path, so this is a Track A
change under the self-host gate and wants doing in one pass rather than
incrementally.

## Interim option, if the full fix is not being taken

Make a non-constant default a LOUD error rather than silently None. Strictly
better than today — but check the uforth corpus first, because the current
silence is what lets its native-word bodies compile at all, and that is the
reason the behaviour exists.

## Gate

A `.npy` diffed against CPython: empty `[]`/`{}`/`()` defaults; a name default
bound to both a scalar and a container; the accumulator idiom across three calls
(pinning the SHARED semantics, not fresh-per-call); a default referring to an
enclosing local, called both directly and as a returned closure; and every
constant-default form as a regression control.


## 2026-08-02 — MODULE-LEVEL defs fixed and landed (commit e53fa4a3f); methods and nested defs still open

The "Shape of the real fix" plan was taken as written, and it was right — with
one correction and two adjacent bugs found on the way.

**The correction to step 4.** The ticket says the omitted-argument fill happens
at four sites in `parser.inc`. Those four are all inside ONE funnel,
`DefaultArgValueNode`, so the shared-path change is a single branch. But that
funnel is not the site a NilPy call actually uses: the real fill for a `.npy`
call is the IR-level loop in **`ir.inc` (~8007)**, keyed on the same
`ProcParam*` arrays. Both are wired now; measuring which one fires is what found
it — the first build stored the symbol correctly and the call site never read it.

### What landed

- `PyEvalParamDefault` parks the header cursor (`j` is a token INDEX; the header
  is walked by index, not by the cursor), parses the expression, allocates the
  hidden global and queues `$pdef.<proc>.<param> := <expr>`.
- `PyDefInitHead`, a queue of its OWN. Not `PyHoistHead`: `PyParseDef`
  deliberately discards the hoist queue on the way out, and these initialisers
  come from the HEADER and must survive that. `PyCollectLocalsAST` parks and
  restores it, and the trial rounds clear it — missing either one silently
  dropped every initialiser and the global read as zero.
- The value's OWN hoisted setup is spliced in ahead of the store. A list literal
  is `pylist_new` plus an append per element, all hoisted; left on the hoist
  chain they were discarded and `len(b)` reported "expected an object with a
  length, got object" — a list that was never built.
- `ProcParamDefaultSym` is a PARALLEL ARRAY, per the ticket's step 3.
- `PyParseDef` records the symbols UNCONDITIONALLY, because the common case
  reaches neither `PyApplyDefSignature` branch: a def whose shell
  `PyRegisterDefShells` already registered keeps that Proc untouched, and the
  shell pass parses headers with evaluation off.

### Two adjacent bugs, both confirmed pre-existing against a stashed baseline

- **`def f(b=1+2)` failed to PARSE.** The constant path claimed the `1` without
  checking that it ENDED the default, so the cursor sat on `+` and the header
  died on "Expected: )". A literal is now the constant default only when the
  next token closes it (`,` or `)`); everything else takes the expression path.
  This is why the ticket's own table has no compound-expression row — the form
  could not be measured.
- **`def f(b=True)` printed 1.** Recorded as the ordinal 1 and boxed as an
  integer. `ProcParamDefaultIsBool` boxes it `tyBoolean`.

### Verified

`test/test_nilpy_param_defaults_nonconstant.npy` (+ `.expected`, wired into
`make test-nilpy`): `[]`, `{}`, `()`, `[1,2]`, a name bound to a scalar and to a
container, compound expressions, every constant form as a control, an explicit
argument overriding a default — and **the accumulator idiom across calls**,
which pins the SHARED semantics rather than fresh-per-call. Byte-identical to
CPython.

The uforth corpus, which the ticket flags as the reason the old silence existed,
stops at the SAME pre-existing wall (line 3887, "expected newline after
statement") on a stashed baseline build and on this one — measured both ways, so
the change neither helps nor hurts it.

## STILL OPEN — two paths keep today's None behaviour

1. **METHOD defaults** (`def go(self, b=[])`). Methods do not go through
   `PyParseDefHeader` at all: their defaults are recorded by
   `PyRegisterClassMembers`, a token-INDEX pre-pass with no cursor, which runs
   before the class statement's position in the stream. Evaluating there is
   wrong — Python evaluates a method default when the CLASS BODY executes, so
   the initialiser belongs at the class statement, which means routing it
   through `PyParseClass` rather than the member pre-pass. Separate plumbing,
   not a flag flip.
   *Update, commit ce45555ec:* the PARSE half is fixed. Both skip sites in the
   method header stepped exactly ONE token past the `=`, so a container default
   on a method was a hard error rather than a None — the None behaviour was not
   even reachable for those forms. `PySkipParamDefaultAtCursor` now balances
   brackets like `PyParamDefaultAt` does on indices. A method's `b=True` also
   printed 1 (the member pre-pass did not carry `ProcParamDefaultIsBool`) and is
   fixed with it. So what remains for methods is only the EVALUATION, and the
   route is known: the initialiser must be queued from `PyParseClass`, at the
   class statement, since Python evaluates a method default when the class body
   executes.
2. **NESTED defs** (`def inner(b=q)` over an enclosing local). Queued at their
   `def` statement and compiled AFTER the enclosing routine's epilogue, so by
   the time the header is parsed the enclosing scope is gone and evaluating
   would report `q` undefined. Evaluation is explicitly disabled for them
   (`PyNestPrefix <> ''`). The closure-VALUE path already evaluates these
   (`PyNestedDefClosureValue`); the direct-call path would need the default
   evaluated at `PyQueueNestedDef`, where the enclosing scope IS live.

## 2026-08-04 — METHOD half ATTEMPTED and REVERTED; the route works, but it corrupts on the SECOND class

Recording a negative result, because it rules out the obvious plan and leaves a
much narrower question than "how would you do this".

### The plan works — for one class

`PyEvalMethodDefaults(ci, bodyStart, bodyEnd)`: walk the class body's `def`
headers by token index, and at each top-level `=` call the existing
`PyParamDefaultAt` with `PyDefaultEvalMode` ON, so the constant-vs-expression
rule and the span skipping stay in one place. It hands back the hidden global in
`PyDefaultSym`; store that into `ProcParamDefaultSym[mpi * MAX_PROC_PARAMS +
pIdx]` (parameter 0 is `self`), and flush `PyDefInitHead` at the class statement
the way the `def` branch already flushes at the def statement. The hidden
global's name must carry the CLASS (`$pdef.<Class>.<meth>.<param>`) or two
classes with the same method and parameter names share one slot.

Measured working with that in place:

```python
class C:
    def go(self, b=[]):
        b.append(1)
        return b
    def sc(self, b=7):
        return b
print(C().go(), C().sc())    # [1] 7 — correct, was AttributeError on NoneType
```

### The wall: a SECOND class statement corrupts unrelated values

```python
class A:
    def f(self, b=[1]):
        return b
class B:
    def f(self, b=[2]):
        return b
print(A().f(), B().f())      # want [1] [2]; got two raw POINTERS
```

Everything in the file then prints as a pointer — including a module-level
`def f1(b=[])` declared BEFORE either class, and including files where only
`f1()` is printed. So it is not "the second class is wrong", it is that the
second class's evaluation corrupts state the whole compile depends on; printing
as a pointer means `print` bound its Int64 overload, i.e. the values lost their
container type.

Narrowed by measurement:

| shape | result |
| --- | --- |
| one class, one container default | OK |
| one class, TWO container defaults | **OK** |
| two classes, CONSTANT defaults | OK |
| two classes, one container default each | **corrupt** |

So it is two class STATEMENTS that each allocate a hidden global — not two
allocations (one class with two is fine), and not two classes as such.

### What is NOT the cause

Evaluating from inside `PyParseClass` was suspected — its trial parses and
symbol rollbacks are exactly the hazard — so the evaluation was moved OUT to the
statement loop (recording the body span in globals set by `PyParseClass`, then
calling the evaluator after it returns, beside the existing `PyFlushDefInit`).
**The corruption is identical either way.** Do not spend the same hour on that
hypothesis.

### Where to look next

Something about the per-class-statement flush/arena interaction, not the
evaluation itself. Concretely: whether the AST nodes of the FIRST class's queued
initialiser survive the SECOND class's parse (`ASTArenaFloor` is raised at the
class branch, which should protect them — verify that it actually does), and
whether `AllocVar` of the second hidden global disturbs a symbol the first one's
type resolution still points at. Measure with `PXXDBG=n.locals` on a two-class
file and compare the globals' TypeKind against the one-class file, rather than
reasoning about the arena.

The change is reverted; the tree carries none of it. The METHOD half and the
NESTED-def half (unchanged, see above) both remain open.
