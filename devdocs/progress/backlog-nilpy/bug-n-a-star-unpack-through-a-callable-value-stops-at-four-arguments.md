---
slug: bug-n-a-star-unpack-through-a-callable-value-stops-at-four-arguments
track: N
prio: 45
type: bug
blocked-by: []
status: open
found: 2026-09-13
found-by: frankH
owner: frankH
summary: "The LADDER is widened to eight and this ticket is what remains: the
  callable-VALUE road is still a per-arity ladder, where the METHOD road became
  list-taking (pydyn_methl, 95e7eb26e). A star-unpack through a name bound to a
  def used to stop at FOUR -- lekkerzeilen died at run time on
  `_quad(out, *quad)` (lines.py:782 and three more), one written argument plus a
  four-tuple into a five-parameter def, which CPython accepts. Widened to eight
  because a callable value is called THROUGH ITS CODE ADDRESS and an indirect
  call needs a STATIC arity, so the arms must be enumerated: TPyCallFn5..8,
  TPyCbF/FP/M/MP 5..8, pyvar_callv5..8, pybound_callv5..8. Eight is loud when it
  overflows and the refusal now NAMES the callee. What remains is that the
  ceiling exists at all -- the non-ladder answer is written below so the next
  seat does not simply widen it to sixteen."
---

# A star-unpack through a callable value stops at four arguments

## The fact, and what it cost

```python
from .geometry import _quad          # a DOTTED from-import binds a VALUE
_quad(out, *(quad if side > 0.0 else tuple(reversed(quad))))
```

`lekkerzeilen/lines.py:782`, and 813, 965, 1222. One written argument plus a
four-element star, into `def _quad(out, a, b, c, d)`. At run time:

```
Unhandled exception: TypeError: forwarded call got 5 arguments, expected 0 to 4
```

It named no callee, which is its own finding — see below.

Reduced to three files, no lekkerzeilen: a package whose `lines.py` does
`from .geometry import _quad` and calls it with a star. The discriminator is the
DOTTED module path, measured:

| shape | before |
| --- | --- |
| `from geo import _quad` (single-segment module) | works |
| `from . import geometry` then `geometry._quad(*xs)` | works |
| `from .geometry import _quad` (relative, name) | **refused** |
| `from pkg.geometry import _quad` (absolute dotted, name) | **refused** |

So a `from <dotted> import <name>` binds the name as a callable VALUE where a
single-segment one resolves it to a proc. **That is not itself the bug** — binding
a name to a value is what CPython does, and pxx resolving it statically is an
optimisation. The bug is that the value road refused an arity CPython accepts.

The carrier turned out to be the `{code, recv}` PAIR (tag 8, `pycallback_is`),
which is what a plain def bound to a name becomes — not the raw code address the
first guess assumed. Found by widening the raw-address rung first and watching the
refusal move to `a bound method reached as a value takes at most 4 arguments`.

## What was done

Eight where there was four, on every road a wide call can take:

- `pyvar_callv5..8` (pyeval) over one shared `pyvar_wide_prelude`, so the four
  rungs differ only in the indirect call — which is the one thing a static arity
  is needed for.
- `pybound_callv5..8` (pylib) and `PyBoundCallV` / `pybound_pair_call` /
  `pybound_pair_call_kw` / `PyBoundPairCallKwBody` widened to eight slots.
- `TPyCallFn5..8`, and `TPyCbF/TPyCbFP/TPyCbM/TPyCbMP 5..8` — **four families,
  because each is a different calling convention** and three of the four would
  otherwise stay unexercised: a plain function, a `-> None` function (a real
  Pascal procedure — casting one through the function types reads a garbage
  hidden-result pointer and the callee's epilogue writes 16 bytes through it), a
  bound method, and a `-> None` method.
- `PyStarDynCall`'s arm chain and `PyMakeDynCall`'s dispatcher selection, the
  latter also closing a hazard its own comment described: arities 5+ used to take
  the AN_CALL_IND lowering, *"correct for a plain def and a SEGFAULT for a
  lambda"*.
- The default fill in `PyBoundPairCallKwBody` was gated on `want <= 4`, so a wide
  call would have skipped it and the body would have read whatever was in the
  slot. Now `<= 8`.
- `PyBoundCallStar` (a COLLECTING callee) carries four fixed slots and was
  unreachable past four until this widening. It now REFUSES by name rather than
  dropping the surplus — which in a collecting callee lands in neither a
  parameter nor the tuple.

## Why eight, and why the ladder is not the answer

**The ladder is structural, not a preference.** A callable value is called through
its code address, and this compiler has no variadic indirect call: an indirect
call needs a static arity, so the arms must be enumerated somewhere. The METHOD
road escaped this (`pydyn_methl`, `95e7eb26e`) because it dispatches through RTTI
and `PyHostCall`'s binder already takes a `TPyList`. The value road has no such
binder — it has a bare code pointer.

Eight because the widest star-unpack in the lekkerzeilen corpus is seven
(`Grid(*row[1:])`), with one to spare.

**THE CEILING IS A CAP AND THIS SENTENCE IS WHY IT WILL NOT GO SILENT:** every
overflow raises, and the refusal now names the callee and the ceiling. The failure
mode to avoid is the one frankuser hit from the other side this week —
`PY_MAX_FIELD_CANDIDATES = 16`, where candidates past the cap were dropped
*without being counted*, and which survived because nobody wrote down that the cap
was a cap.

**The non-ladder answer, so the next seat does not widen eight to sixteen.** A
trampoline: one entry point taking a `TPyList`, which marshals the arguments into
the platform's own argument registers/stack and jumps to the code address —
`PyHostCall`'s pointer-family arm already does exactly this shape for up to five
(`pa: array[0..4] of Int64`, `pvHold` for the by-address Variants), so the
mechanism exists and only its own ceiling and the per-ABI half are missing. That
is the work: generalise that marshalling loop to N and give the value road the
same door the method road got. It is a Track A / ABI job rather than a frontend
one, which is why it was not taken alongside a demo wall, and it retires this
ticket, the four TPyCb* families, and `MAX_STAR_DYN` together.

## The diagnostic was half the cost

`forwarded call got 5 arguments, expected 0 to 4` named **no callee**, out of a
binary with 11711 procedures. Locating it meant an AST census over 34 modules for
every def whose parameters are all defaulted: eight candidates and no answer.
`pystar_check_arity` and `pystar_check_arity_kw` now take the callee's name, and
`PyStarGuardName` appends it at all five emit sites so a sixth added later cannot
go back to the nameless form. The name goes in FRONT of the existing sentence, so
the wording two Makefile assertions, four fixtures and several tickets already
quote is untouched.

For a callee reached as a value there is no `Procs[]` entry to ask, so
`PyDynCalleeName` takes the source spelling — the variable for `fn(*xs)`, the
attribute for `h.cb(*xs)`, and the identifier token before the `(` otherwise. It
must be read BEFORE the argument list is parsed, because that last arm is
token-positional.

## Test

`test_nilpy_wide_call_through_a_callable_value.npy`, `.expected` from CPython:
all four carrier families at 5 and 8, defaults filled at a wide arity, written
arguments as well as a star, a written argument BESIDE a star (the arrangement a
star-only fixture never reaches), a lambda (the closure road, which never had a
cap), and an attribute holding a callable.
