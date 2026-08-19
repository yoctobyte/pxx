---
track: N
prio: 55
type: feature
status: done
---

# A Nil Python generator can only be consumed by a `for`, never held as a value

Generators landed in [[feature-nilpy-yield-outside-a-for-loop]] and cover the
shape the third-party corpus is made of: a `def` or method that yields,
consumed directly by a `for` over the CALL —

```python
for x in gen(args): ...
for t in obj.gen(args): ...
for token in Base.__iter__(self): ...
```

Every other way Python touches a generator is unsupported:

```python
g = gen()               # a generator OBJECT
list(gen())             # consumed by a builtin
next(g)                 # the iterator protocol by hand
other(gen())            # passed as an argument
for t in some_object:   # iteration through __iter__, not through a call
```

**These are compile ERRORS today, not wrong answers** — the step ABI injects a
hidden `__genself` parameter, so a source-level call never matches arity. That
is the good failure mode and it should stay: whatever replaces it must not
quietly start calling a step function.

## Why it is not just more parsing

The desugar allocates the instance, seeds the argument slots, drives the step
function and frees it, all inside one `for` statement — the generator has no
lifetime of its own. A VALUE needs the instance to outlive the expression that
made it, which means an object with the instance pointer, the step function's
address, and a `__next__` that calls it. PXX cannot call through a stored proc
pointer with arguments (the desugar's own comment records this), so the step
call has to stay a direct call the compiler emits, or that restriction has to
go first.

The consumption side then wants the FPC structural enumerator protocol that
`parser.inc` already implements — `GetEnumerator` / `MoveNext` / `Current` —
which is where `for t in some_object` should land: `__iter__` -> `GetEnumerator`,
`__next__` -> `MoveNext` + `Current`, `StopIteration` -> False.

## Reach

Not measured against the corpora. Measure before ranking: the ladder's files
were unblocked by the CALL form, so this may buy less than it looks. That is
why `prio:` sits below the shim work rather than beside it.

## LANDED 2026-08-19 (Track A+N) — every consumption form works

Three commits on master:

| sha | what |
| --- | --- |
| `091728229` | a generator call in value position becomes a cursor |
| `8e540be59` | an object whose `__iter__` yields is iterable |
| `9cc61eee2` | fix: the for-in desugar swallowed the statement after it; the cursor frees its instance |

**Every differential probe in the suite now matches CPython, with no exceptions.**
Covered: `g = gen(args)`, `next(g)`, `list(g)`, a generator passed as an
argument, multi-stage pipelines, a generator partly consumed by `next` and then
resumed by a `for`, and the full html5lib filter architecture — a base `Filter`,
two subclasses each chaining to `Filter.__iter__(self)`, composed and iterated.

### The design in this ticket was wrong, and measuring is what caught it

Written yesterday from the desugar's own comment, inherited rather than tested.
Both load-bearing claims were false:

- **"PXX cannot call through a stored proc pointer with args."** It can. A
  generator driven entirely through a function pointer in an object field runs
  correctly at HEAD; that was the first thing measured and it changed everything.
- **"A value needs an object with the instance, the step address and a
  `__next__`."** pylib already HAS that object: `TPyIter`, the lazy cursor behind
  `map`, `filter`, `zip`, `reversed` and generator expressions, with a two-call
  prefetch protocol. A generator value is one more KIND — `PYITER_SLGEN`, two
  fields, one advance arm — and every consumer was then already written.

So the feature was a day's work rather than a redesign, and the ticket that
described it would have led the wrong way. **Check a ticket's premises against
the code before planning around them, even when you wrote the ticket.**

### `__iter__` needed a generated method, and the FIRST design was wrong too

`__iter__` is the hook the RUNTIME calls, and a generator method is a
state-machine step function with a `(instance, self) -> Boolean` ABI. pylib could
not call it and never tried (`PyUserObjNoArgDunder` requires arity 1), so such an
object was correctly reported as not iterable.

Mangling `__iter__` out of the way and synthesizing a stand-in under that name
was tried first and **abandoned before it was written**: the generated method
inherits the virtual SLOT of the base class's `__iter__`, whose override
numbering is keyed on the SOURCE token, so a subclass and its base would disagree
about the VMT layout. The landed design adds a SEPARATE name
(`__pxx_gen_iter__`), which is purely additive — fresh slot, ordinary
`FindUMeth` parent walk, every existing route untouched — and non-virtual,
because it is registered after the class body is parsed and claiming a slot then
would renumber a layout earlier subclasses already committed to.

### Two bugs found on the way

- **The shadow guard used `FindSym`**, which also answers for a PARAMETER symbol
  left behind by an RTL unit's routine. A user generator named `src` — a
  parameter name in `json.pas` and `ed25519.pas` — was silently refused and fell
  through to be CALLED, while the same generator named `gen` worked. Only
  `PyProgSym` answers "does the PROGRAM bind this name".
- **The for-in desugar swallowed the statement after it**, one level in. It
  returns an AN_SEQ, which PyParseBlock does not count as block-consuming, so the
  block was eaten twice. Present since generators landed; invisible at module
  level, which is where every probe had been written.

### Corpus, scored the same way as before

html5lib non-test compiles are **still 7 of 33, unchanged.** No wall moved,
and none was expected to: every gap this ticket closed was a RUNTIME capability,
not a parse error. What changed is that generator-based code now EXECUTES
correctly rather than merely compiling — demonstrated on a faithful
reconstruction of the html5lib filter architecture, not on html5lib itself,
which still stops on unrelated walls (slicing, `*`-unpack, missing modules).

Worth stating plainly: **the compile count is the ladder's metric and it did not
move.** This work is a precondition for those files doing anything useful, not
progress along the metric.

### Memory, measured

20 000 generators: **2.5 MB** peak through the `for` desugar, **6.5 MB** as
values — flat, not growing without bound. A cursor now frees its instance block
at finalization; the managed values in the persistent slots are still dropped
unreleased, which stays
[[bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells]].

### Still not supported

`yield` inside `try` or `with` (the stackless transform's own limit, measured as
zero occurrences across the ladder corpora), `yield from`, `.send()` / `.throw()`
/ `.close()`, and more than 6 generator parameters. None of these appear in the
corpora; all are compile errors rather than wrong answers.

**PIN NOTE:** this work touches `compiler/builtin/pylib.pas`, so other lanes do
not see `pygen_iter_new` or the cursor kind until a pin. Verified at HEAD only.

## Log
- 2026-08-19 — resolved, commit c29df36b1.
