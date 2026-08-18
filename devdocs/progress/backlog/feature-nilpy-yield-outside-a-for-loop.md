---
track: N
prio: 58
type: feature
status: working
owner: frank2-7e
---

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
