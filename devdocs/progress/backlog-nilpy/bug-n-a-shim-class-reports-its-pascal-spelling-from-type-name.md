---
slug: bug-n-a-shim-class-reports-its-pascal-spelling-from-type-name
type: bug
track: N
prio: 25
status: open
summary: "`type(collections.deque()).__name__` answers `TPyDeque` where CPython answers `deque`, because the Python-facing name is a type ALIAS and `__name__` reports the declared Pascal class. The alias makes construction and annotation work, so the gap is invisible until a program introspects — and introspection is exactly where a program has been told it can trust the answer. A CLASS, not one row: every shim that aliases around a name collision (`lib/rtl/pil.pas`'s `Image = TPILImage`, and any future one) has it, so the fix belongs wherever `__name__` is derived, not in the units."
---

# A shim class reports its Pascal spelling from `type(x).__name__`

Measured 2026-09-21 at pxx `8e60c44be`, and again under the **pinned** compiler,
which is how it was attributed: it turned up as a false hit in an unrelated
change's positive control, and reproducing it on the pin is what separated
"pre-existing" from "I just broke this".

    import collections
    d = collections.deque()
    print(type(d).__name__)

    CPython 3.14.4 : deque
    pxx            : TPyDeque

## Why it exists

A shim cannot always spell the Python name directly — `lib/rtl/pil.pas` records
the sharp version of this, where declaring a class named after a unit in its own
`uses` clause **silently miscompiles the constructor into a self-call**. The
established workaround is to declare the class under a Pascal-ish name and
publish a type ALIAS:

    Image = TPILImage;

The alias is enough for construction, for annotation and for qualified access,
so everything a program normally does keeps working. `__name__` is derived from
the DECLARED class, so it keeps reporting the internal spelling.

## Why the prio is 25 and not lower

It is introspection-only and no demo depends on it, which is the whole argument
for a low number. What keeps it from being `rejected/`:

- **`__name__` is an instrument, and this is an instrument lying.** The tree's
  own `SizeOf` ruling says a truthful instrument reporting a surprising answer
  is not a defect — *"sizeof reported CORRECTLY about the accurate type"*. This
  is the other case: `TPyDeque` is not a true statement about anything the
  program can name. There is no pxx-level type called `TPyDeque` that a NilPy
  program could have written or could reference.
- **It is a CLASS and it grows.** Every alias-around-a-collision shim has it.
  Two exist today (`deque`, `TPILImage`); the pattern is the recommended
  workaround, so the population only goes up.
- The failure is silent and the value is plausible, which is this tree's
  expensive shape.

## Not the fix

Renaming the Pascal classes to their Python spellings. That is what the alias
exists to avoid, and in `pil.pas`'s case it reintroduces a silent miscompile.

## What would probably fix it

Carry the Python-facing name on the class and have `__name__` prefer it — the
alias already records the intended spelling, so the information exists and is
simply not reaching the accessor. Whoever takes this should check what
`__qualname__`, `repr()` and `isinstance` error text do with the same name,
since a partial fix here is the sibling-spelling trap.

## What would retire this

`type(collections.deque()).__name__` answering `deque`, with a row for the
`pil.pas` alias in the same fixture so the second spelling is not left behind.
