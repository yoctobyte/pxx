---
track: N
prio: 75
type: feature
status: working
owner: frank2-7e
---

> **RERANKED 58 → 75 on 2026-08-18, and the reason inverts the campaign's standing
> assumption.** A Track B re-measure at pinned v352 (`0d2087d6…`, pin `b14da0847`)
> found the missing-module batch had *already shipped* — what remains is **8 files, 4 of
> them behind one Track U decision**, while the LANGUAGE walls are **32**. `yield` alone
> is **18 files — more than every missing-module row combined.** Track N is the
> bottleneck for this ladder again; the earlier "Track N is no longer the bottleneck"
> read was measured before those shims landed and is superseded.
>
> **DISPATCH CONSTRAINT — this is SCHEDULED work, not queue work.** Despite now topping
> Track N, it must NOT be handed to a long-running session just because `next` ranks it
> first. Its remaining failure mode is **silent stack corruption** in `PyEmitParamSpills`,
> not a compile error, and that is the worst possible thing to chase on a thin context.
> It is smaller than the body below claims (the generator engine is built and proven for
> Pascal — `slgen.pas`, stackless, working today), it is **NOT** blocked on
> `decide-how-a-compiled-def-carries-its-signature-when-boxed`, and the diagnosis is
> banked so a fresh session starts from it. Give it a fresh session with room.

# `yield` only works inside a `for` — a while-loop generator does not compile

```python
def gen(n: int):
    i = 0
    while i < n:
        yield i          # error: undefined variable (yield)
        i = i + 1
```

The same generator written with `for i in range(n): yield i` also fails today,
so the working surface is narrower than the "for-in/yield" support suggests —
worth establishing exactly which shape does work before starting.

`yield` reported as an "undefined variable" says it is not being recognised as
a statement at all in this position, so the parse arm is keyed to a context
rather than the keyword.

Found by sweeping generator/ternary/unpacking constructs against CPython.

## Recon 2026-07-31 — bigger than the title suggests, not attempted

Measured, not assumed: `grep -n "'yield'" compiler/pyparser.inc` returns ZERO
matches. `yield` is not recognised ANYWHERE in the NilPy frontend today — not
"works inside `for`, fails inside `while`" as the title implies, but
unimplemented full stop. Confirmed directly: `for i in range(n): yield i`
(the shape the title says already works) ALSO fails with the same "undefined
variable (yield)" — matching the ticket body's own footnote, not the title.

`CurProcIsGenerator`/`CurGenSelfSym`/`GenTryDepth` and the "stackful
coroutine body" machinery mentioned around `PyParseDef` (pyparser.inc) exist
for a Pascal-only `; generator;` directive — there is no NilPy-side wiring
to it, automatic or otherwise. So this isn't a parse-context bug to
relocate; it's full Python generator support to build: recognising a
`yield`-containing `def` as a generator automatically, giving it suspend/
resume semantics (there IS a coroutine backend to potentially reuse, just
not connected), and the iteration protocol (`for x in gen()`, `list(gen())`)
on top. Sized like the other bigger, dedicated-pass features in this
backlog (`feature-nilpy-lambda-compiled-closure`, closure-ABI items), not
like a quick bug fix. Not attempted this session — retitling the fork
correctly (unimplemented feature, not a narrow context bug) is the useful
output of this recon.

## Gate

`make test-nilpy` + self-host byte-identical, plus generators driven by
`while`, by `for ... in range`, and by `for ... in <list>`, each consumed by a
`for` loop and by `list()`.

## Corpus evidence 2026-08-18 (frank2-7e, Track N)

From the ladder A/B in [[feature-nilpy-thirdparty-libraries-as-targets]], at HEAD
`c7974b6af`. **The 2026-07-31 recon is confirmed exactly** — re-measured before
adding anything, because this ticket's own title had already been wrong once:

| shape | result |
| --- | --- |
| `def g(): for x in [1,2]: yield x` | `undefined variable (yield)` |
| the same with an `if`/`elif` chain before the `yield` | same |
| the same as a METHOD (`def __iter__(self)`) | same |

So no `yield` shape works, `for`-driven included. The **title remains wrong** and
the recon section is right; anyone reading only the title will size this as a
context bug.

**Reach — this is the number for ranking.** The ladder's first-wall table counts
`undefined variable (yield)` at 3 files, which badly understates it: a first-wall
table only ever sees the file's FIRST error, and most `yield` users stop on an
earlier wall today.

Files that USE `yield`, in the ladder corpora (67 `.py` total):

| corpus | files | use `yield` |
| --- | ---: | ---: |
| html5lib | 52 | **21** |
| tinycss2 | 10 | 1 |
| webencodings | 5 | 1 |
| **total** | **67** | **23** |

**23 of 67 — but 9 of those are `html5lib/tests/**`.** Corrected after compiling
each of the 23 and reading its first wall: the decision-relevant figure is
**14 library files**, not 23. Stating both because the raw 23 was published first
and is the more flattering number; the test files are real users of `yield` but
nobody's build is gated on them.

html5lib is a streaming tokeniser/filter/serialiser pipeline, so generators are
its spine rather than a convenience — `_tokenizer.py`, `serializer.py` and every
`filters/*.py` are generator-based. No amount of shim work reaches those files.

The three whose FIRST wall is `yield` today, i.e. the files this feature alone
would unblock:

- `html5lib/filters/inject_meta_charset.py`
- `html5lib/filters/optionaltags.py`
- `html5lib/filters/whitespace.py`

The other 11 library users sit behind a module shim first (`sys`, `xml_dom`,
`xml_etree_elementtree`, `xml_sax_saxutils`, `genshi_core`) — so `yield` and the
Track B shim work **compound**: neither alone opens the pipeline, and the shims
landing without `yield` would move 11 files onto this wall rather than past it.
That is the argument for ranking it alongside the shims rather than behind them.

Recorded as evidence only. Ranking is the coordinator's and the user's call —
`prio:` deliberately untouched.

## Reranked 35 -> 58 by the coordinator, 2026-08-18 — on corpus evidence

Rank follows evidence rather than preceding it, so this moved only once the files were
named. Three corpus files stop on `yield` and nothing else
(`html5lib/filters/inject_meta_charset.py`, `optionaltags.py`, `whitespace.py`), and 11
more reach it once the module shims land.

Placed at 58 rather than at the shim ticket's 60 deliberately: the shims unblock more
files outright, but these two **compound** and neither alone opens html5lib's pipeline.
Scheduling them in the same window is the point of the number, not the ordering between
them. See [[feature-b-module-shims-for-the-html5lib-corpus]].

**Title warning, raised by frank2-7e and left in place rather than fixed here:** this
ticket's title has already been wrong once, and it is still wrong. The 2026-07-31 recon
was re-measured 2026-08-18 and is exactly right — **no** `yield` shape works, including
the for-driven and method forms the title implies are fine. Anyone sizing this from the
title alone will read it as a context bug and under-scope it. Retitling is a hygiene
call left for whoever takes it.

## SCOPED 2026-08-18 (frank2-7e) — strategy de-risked, then PARKED UNSTARTED

Claimed, measured, not started. No compiler file was touched. The measurement
below removes the main unknown so the next session does not have to decide the
strategy first.

### Confirmed a third time: nothing exists on the NilPy side

`grep -c "'yield'" compiler/pyparser.inc` -> **0**, and the NilPy lexer has no
yield token either. The 2026-07-31 recon stands: yield is unimplemented
outright, not broken in a particular context. The TITLE still says otherwise --
flagged, not retitled unilaterally.

### What DOES exist, and it is a lot

A complete Pascal generator feature, in **two** strategies that deliberately
share a consumption interface:

- **stackful** -- `; generator;` + `lib/rtl/coroutine`, a real 64 KB heap stack
  per live generator (`CO_STACK_BYTES`), switched by `CoSwitch`.
- **stackless** -- a state-machine transform in `parser.inc` (`SLCheckEligible`,
  `MAX_GEN_STATES = 1024`) over `lib/rtl/slgen.pas`, persisting locals in slots.

`defs.inc` records the key property: *"Share CURRENT/DONE offsets with the
stackful layout so for-in reads the value/done flag identically for either
strategy; only the advance step differs."* And `for x in Gen(args)` already has
its desugar in `parser.inc`.

So the runtime, the state machine, slot persistence and the iteration protocol
all exist. What is missing is NilPy-side wiring, not generators.

### THE STRATEGY QUESTION IS SETTLED -- by measurement, not by argument

The stackless transform refuses `yield` inside a `try`, inside a `with`, and in
an `if`/`while`/`for`/`case` *condition*; it allows yield at top level and in
those constructs' bodies. The obvious worry is that real Python generators wrap
a yield in `try`/`finally`, which would force the stackful path -- 64 KB per live
generator, in a tokeniser pipeline that keeps several open at once.

Measured over every non-test generator in the ladder corpora (html5lib,
tinycss2, webencodings) using CPython's own `ast` module:

| | |
| --- | ---: |
| generator functions (excluding `tests/**`) | **19** |
| total `yield` sites | **76** |
| generators with a `yield` inside `try`/`with` | **0** |

**Zero.** Stackless covers the entire corpus, so this can be built on the cheap
path with no 64 KB stack per generator. That was the single biggest open risk
and it is now closed.

### What the corpus needs is the METHOD form, not the module-level one

The files whose first wall is `yield` are html5lib filters, and each is the same
shape:

```python
class Filter(base.Filter):
    def __iter__(self):
        for token in base.Filter.__iter__(self):
            yield token
```

A generator **method**, returned from `__iter__`, consumed by `for t in
filter_instance`. So the tempting first increment -- a module-level `def` with
yield driven by `for x in gen()` -- appears **nowhere** in this corpus and would
move **zero** files. Whoever lands that half should report it as groundwork, not
as ladder movement. (Same trap as the first-wall/reach split already recorded on
the campaign: work that moves files ONTO the next wall is progress-shaped.)

### Implementation order

1. NilPy lexer: a `yield` token (none today).
2. `pyparser`: a pre-pass marks a `def` whose body contains `yield` as a
   generator -- Python decides this at compile time from the body, which matches
   the existing `PyScanLo` pre-passes over a module's token span.
3. Lower the marked def onto the **stackless** transform. **This lands in
   `parser.inc`** (`SLCheckEligible` and the state-machine builder live there) --
   a shared file, so it needs the A/P slot declared.
4. The iteration protocol: a generator object returned from a call, and `for x
   in <it>` over it. This is what the corpus needs and the largest piece.
5. The module-level `for x in gen()` form then falls out.

### Why parked rather than started

A dedicated pass, as the recon said and as the corpus evidence confirms: 19
generator functions, a full iteration protocol, landing in shared files. Steps
1-3 move no corpus file on their own, so a partial landing would be a
feature-shaped commit with nothing to show plus a new half-state in
`parser.inc`.

Returned to `backlog/` rather than `unfinished/` deliberately: nothing is
half-applied, so the queue should rank it as available work, not as a lock.

### Open question for whoever takes it

Generators are stateful objects. If step 4 needs a callable value to carry
state, read `decide-how-a-compiled-def-carries-its-signature-when-boxed` FIRST
-- it is the same representation question, still with the human, and
pre-empting its ruling would be wasted work in a lifetime-sensitive area.

## Coordinator note 2026-08-18 — this ticket now DEPENDS ON A PENDING DECISION at step 4

Recorded here rather than as a `blocked-by`, because steps 1-3 are genuinely independent
and blocking the whole ticket would hide available work. But **step 4 (the iteration
protocol, the largest piece) may need a callable to carry state, which is the same
representation question as
[[decide-how-a-compiled-def-carries-its-signature-when-boxed]]** (U, p88, with the
human).

**Read that ruling before starting step 4, or you will build the wrong object twice.**
That decision now gates three items: the p88 procedural-value bug, the p85 def-rebinding
bug, and this step.

### The dispatch trap, and it is the day's recurring shape

**The corpus needs the generator METHOD form** — `def __iter__` with `yield`, consumed as
`for t in filter_instance`, which is what the html5lib filters are. The tempting first
increment, a module-level `def` driven by `for x in gen()`, **appears NOWHERE in these
corpora and would move ZERO files.**

So a session could land the lexer token, generator marking and the stackless lowering,
have a genuinely working feature, and move the ladder not at all. **If a future report
says "yield landed", ask WHICH SHAPE before believing any count moved.** Same
first-wall-understates-reach trap as
[[feedback_measuring_a_thing_is_not_filing_it]], wearing a different hat.

### Settled by measurement, so it need not be asked again

The strategy question was the biggest open risk and is now closed. Two generator
strategies already exist for Pascal and share a consumption interface by design
(`defs.inc`: both share CURRENT/DONE offsets "so for-in reads the value/done flag
identically for either strategy; only the advance step differs").

- **Stackful** costs a real 64 KB heap stack per LIVE generator — brutal for a tokeniser
  pipeline holding several open at once.
- **Stackless** is a state machine over `lib/rtl/slgen.pas` but REFUSES `yield` inside a
  `try` or `with`.

The textbook worry is that real Python generators wrap yields in `try/finally`. Measured
across every non-test generator in the ladder corpora using CPython's own `ast`:
**19 generator functions, 76 yield sites, ZERO with a yield inside try/with.** Stackless
covers the entire corpus.

**Title:** still says "outside a for loop", implying the for-driven form works. No shape
works — NilPy has no `yield` handling at all (0 hits in `pyparser.inc`, no lexer token).
That title has now misdirected three separate reads and is worth a rename by whoever owns
the campaign.

## Coordinator re-estimate 2026-08-18 (human challenge) — the generator ENGINE is already built

Rene asked whether yield was not already implemented for Pascal and therefore mostly
mechanical. **Measured, and the answer is yes** — this ticket's framing as a
"dedicated-pass feature" overstates the core.

Verified end to end at HEAD, not read from a comment:

```pascal
function Count(n: Int64): Int64; generator; stackless;
begin i := 0; while i < n do begin yield i; i := i + 1; end; end;
for x in Count(4) do WriteLn(x);        ->  0 1 2 3
```

What already exists: the `yield` keyword, the `; generator;` / `stackless;` markers,
`AN_YIELD` (defs.inc:279), `IR_YIELD` (defs.inc:554), **both** runtimes —
`lib/rtl/coroutine.pas` (stackful, 64 KB heap stack per live generator) and
`lib/rtl/slgen.pas` (stackless state machine, no context switch, no heap stack, every
target, zero per-target asm) — and a shared CURRENT/DONE layout so for-in reads either
strategy identically.

What does NOT exist: **any NilPy side at all.** No lexer token, no parser handling. The
earlier "0 hits" measurement was right.

So the honest shape is **wiring a frontend to a working engine**, not building generators.
Steps 1-3 (lexer token, marking a `def` that contains `yield` as a generator routine,
lowering `yield` to `AN_YIELD`) are largely mechanical against machinery that is already
proven, and the stackless strategy is already known to cover the whole corpus (19
generator functions, 76 yield sites, zero inside try/with).

### Where it is genuinely NOT mechanical

The corpus needs the **iteration protocol**, not the function form:

```python
class Filter:
    def __iter__(self):
        for t in self.source: yield t
for token in filter_instance: ...
```

Pascal's model is `for x in Gen(args)` — a generator FUNCTION called in a for-in. Python's
is an OBJECT whose `__iter__` returns a generator. Bridging that is real work, but it is
iteration-protocol plumbing over a finished engine, not generator implementation.

### The boxed-def dependency should be RE-MEASURED before it is believed

This ticket records that step 4 "may want a callable to carry state" and therefore waits
on [[decide-how-a-compiled-def-carries-its-signature-when-boxed]]. **That deserves a
check rather than inheritance:** a stackless generator's state lives in a HEAP RECORD
(`SL_OFF_*`, slgen.pas), not in the callable, and `__iter__` returning that instance does
not obviously require a boxed def to carry anything. If the dependency does not survive
measurement, this ticket is not gated on the human at all — which matters, because it is
the board's largest row at 14 files.

Whoever takes it: measure that first, in an hour, before planning around a decision that
may not apply.

### Correction to the section above: the ITERATION PROTOCOL also already exists

I wrote that bridging Python's `for t in obj` to Pascal's `for x in Gen(args)` was "the
genuinely NOT mechanical" part. **That was wrong — I had not checked whether Pascal has
the object form. It does.**

`parser.inc:19428` implements the FPC structural enumerator protocol:

```
for X in C do BODY   where C has GetEnumerator
  ->  __e := C.GetEnumerator;
      try while __e.MoveNext do begin X := __e.Current; BODY end;
```

Verified end to end at HEAD with a hand-written class — `for v in c do WriteLn(v)` over a
`TColl.GetEnumerator` returning a `TEnum` with `MoveNext`/`Current` prints `10 20 30`.

**So Python's `__iter__`/`__next__` maps onto machinery that is already built and proven**,
essentially one-to-one: `__iter__` -> `GetEnumerator`, `__next__` -> `MoveNext` + `Current`
(with StopIteration as the False return). That is the piece I had flagged as the hard part,
and it is a naming/adaptation job over an existing protocol.

### And the "stackless is deferred" memory is about ASYNC, not generators

Worth stating because it is an easy misread of `defs.inc`. The "STACKLESS (later)" note
sits on **`AN_AWAIT` (54)**, the async/await marker — not on `AN_YIELD` (52). Generator
stackless is DONE: `; generator; stackless;` compiles and runs today (verified: prints
`0 1 2 3`), and `slgen.pas` is a complete state-machine runtime. Nothing about generators
is deferred.

### Revised estimate

Every engine this needs is built and proven for Pascal: the yield keyword, both generator
strategies, and the object-enumerator for-in protocol. NilPy has none of it wired. So this
is **frontend wiring against three finished subsystems**, not a dedicated pass — closer to
the `.npy` lexer/parser work than to an object-model change, and the "dedicated-pass"
framing in this ticket (mine and the parking session's) should not be inherited.

The boxed-def dependency is now doubly suspect: generator state lives in a heap record,
and the consumption side is an enumerator object. **Measure before planning around it.**

## ATTEMPTED AND PARKED 2026-08-18 (frank2-7e, Track A+N) — wired end to end, parked on a frame-layout crash

First session to actually build this rather than scope it. A NilPy generator now
compiles end to end and **prints its first value**, then segfaults. Reverted to a
clean tree — nothing is half-applied in `compiler/**`, `make compiler/pascal26`
converges at HEAD. Banking the wiring and the exact blocker.

### THE DEPENDENCY DOES NOT SURVIVE MEASUREMENT — this ticket is NOT gated

Measured, as the coordinator asked. `decide-how-a-compiled-def-carries-its-signature-when-boxed`
does **not** gate this. Reason: generator *methods* are refused by the engine
outright, so the boxed-callable route was never on the table — and the route that
DOES work needs no callable value at all.

```
stackless generator/async methods are not supported (v1)
for-in: unsupported iterable expression
```

**The lifted route works today.** A generator method lowered to a free function
taking the receiver, consumed as a plain for-in, verified end to end at HEAD:

```pascal
function Filt__iter__(self: TF): Integer; generator; stackless;
...
for v in Filt__iter__(f) do WriteLn(v);
```

Verified including the exact html5lib nested-filter shape — a generator iterating
another generator, with `continue` in the body: prints `10 20 40 50`. Also
verified: stackless generator over **Variant** elements (`1 2 done`), which is
what NilPy values are, and the object-enumerator protocol (`10 20 30`).

So the implementation order in the sections above is sound and step 4 needs no
ruling from Track U. Anyone inheriting the "read the decision first" note can drop it.

### The wiring, as implemented (all in `pyparser.inc` except one shared hunk)

Every step below was reached and worked; listing them so the next session
re-applies rather than re-derives.

1. **No new lexer token needed.** `yield` arrives as an identifier and is handled
   at statement position, next to the `pass` arm.
2. `PyDefBodyHasYield(bodyStart)` — token scan over the def's span, with a
   `nestedDefDepth` counter so a nested `def`'s yield does not mark the outer one.
   (Python decides generator-ness from the body at compile time; this matches it.)
3. `PyApplyGeneratorABI(bodyStart)` — the stackless ABI is
   `function(__genself: Pointer): Boolean`, so the 10 `PyHdr*` arrays shift down
   by one, `__genself`/`tyPointer` is injected at index 0, `PyHdrNParams+1`,
   `PyHdrRetType := tyBoolean`, `PyHdrIsProc := False`.
4. `PyPullSlgenIfGenerators` — scans the module for a statement-start `yield` and
   issues `ParseUsesUnit('slgen')`; **must** be called at BOTH `PyPreScanImports`
   sites or the unit is not in scope.
5. Generator flags set **before** the locals pre-pass, not after — the pre-pass
   trial-parses the body, and with the context unset `yield` is refused there
   first. This cost a cycle; it is the non-obvious ordering constraint.
6. `for x in gen()` routing, plus a shared-file change (declared, A/P slot held):
   `ParseForInGeneratorAST` in **`parser.inc`** is Pascal-only — it does
   `Expect(tkDo)` + `ParseStatementAST`. Made frontend-aware:
   `if isNilPy then Expect(tkColon) + PyParseSuite`. Note **`PyParseSuite`**, not
   `PyParseBlock` — the latter gives `unexpected token` / `expected expression`
   on the NEWLINE/INDENT..DEDENT block.

### The blocker, localised to one procedure

The program prints the first yielded value, then **segfaults with a corrupted
stack** (`bt` shows garbage frames). Localised by experiment, not by reading:

| prologue emitters guarded with `if not isGen` | result |
| --- | --- |
| `PyEmitParamSpills` + `PyInitVariantLocals` + `EmitManagedLocalsZeroInit` | no crash, but **infinite loop printing the first value** — state never advances |
| re-enable `PyEmitParamSpills` alone | **crash returns** |

So `PyEmitParamSpills` (pyparser.inc:27513) is both the frame-corrupter and
necessary for state to persist. It spills incoming argument registers into each
param's frame slot — correct for an ordinary def, wrong here: in the stackless
step ABI only `__genself` arrives in a register, and the declared params 1..n are
**persistent instance slots the transform restores itself**, so spilling them
writes register garbage over live state every step.

**The next thing to try** (untested, this is where I stopped): make the spill
loop generator-aware — spill `__genself` at pointer width and skip indices 1..n
entirely — then re-test whether `PyInitVariantLocals` and
`EmitManagedLocalsZeroInit` can be restored (they must NOT re-zero persistent
slots on resume either, so expect the same shape of answer for both).

### Why parked

Per the standing instruction: it did not land green, so bank and park rather than
iterate. The remaining work is x86-64 frame-layout integration between NilPy's
prologue and the stackless step ABI — bounded and now precisely located, but real,
and the failure mode is silent stack corruption rather than a compile error.

Returned to `backlog/`, not `unfinished/`: the tree is clean and nothing is
half-applied, so the queue should rank this as available work rather than hold a
lock on it. Same call the previous parking session made, for the same reason.
