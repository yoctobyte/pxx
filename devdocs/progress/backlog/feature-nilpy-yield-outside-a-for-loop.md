---
track: N
prio: 35
type: feature
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
