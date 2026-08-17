---
track: A
prio: 55
type: bug
blocked-by: []
summary: "A `.py` module reached by two import spellings is compiled TWICE as two units (`sub` and `pkg_sub`), because the compiled-unit dedupe key is the unit NAME, not the resolved file. Its module body runs twice — CPython guarantees once — giving duplicated registry side effects and two distinct copies of every class, so isinstance across them fails. Same root also makes a relative subpackage import unresolvable. Filed from Track N: both halves live in parser.inc."
---

# A Python module's identity is its NAME, not its FILE — so one file compiles twice

- **Type:** bug (unit resolution / compiled-unit identity) — **Track A**.
- **Filed by:** Track N (frank2), 2026-08-17, from
  [[bug-n-a-subpackage-directory-does-not-resolve-as-a-module]] while working
  the third-party corpus campaign. **Handed up rather than fixed: both halves
  are in `parser.inc`, which is Track A's file.**

## Symptom 1 — a module body executes twice (the serious one)

```
pkg/sub.py        print("sub-init-ran")
                  X = 5
pkg/__init__.py   from .sub import X
                  P = X
main.npy          from pkg import P
                  from pkg.sub import X
                  print(P, X)
```

| | output |
| --- | --- |
| CPython | `sub-init-ran` **once**, then `5 5` |
| pxx | `sub-init-ran` **TWICE**, then `5 5` |

**`5 5` is correct, and that is what makes it expensive.** A test asserting the
visible output passes forever. The defect is in how many times something
*happened*, which no output comparison sees unless the module happens to print
on import — this only surfaced because the probe's `sub.py` had a `print` in it.

### Why it is a bug and not a NilPy laxity

Python guarantees a module body runs exactly once (`sys.modules` is a cache),
and ordinary working code depends on it:

- **registry population** — `codecs.register(...)` at import time is exactly
  this shape, and it is what `webencodings` does;
- **two distinct copies of every class in the module**, so an object built by one
  copy fails `isinstance` against the other. That is the same observable as the
  canonical divergence example (`isinstance(t, list)` answering wrong) arriving
  by a new mechanism, and `devdocs/dev/nilpy-semantics-divergences.md` classes it
  as a real bug rather than an accepted laxity: a program CPython accepts and
  runs can observe it;
- module-level state silently forked into two copies.

### KNOWN LIVE EXPOSURE

`lib/rtl/mimic_codecs.pas` registers codecs at import time. Anything reaching
that shim by both spellings is registering **twice today**, independent of this
fix. Flagged here so whoever touches the shims is not surprised by it.

## Symptom 2 — a relative subpackage import does not resolve

```
pkg/inner/__init__.py   IN = 42
pkg/__init__.py         from .inner import IN     -> error: no unit named inner
main.npy                from pkg.inner import IN  -> works, prints 42
```

## Root cause — one cause, both symptoms

**The relative form and the dotted form name the same file differently**, and
unit identity is that name.

1. `PyConsumeDottedModule` (`pyparser.inc`) builds `pkg.sub` for the dotted
   spelling, which mangles to unit `pkg_sub`. The relative spelling deliberately
   **skips the dots** and passes the bare `sub` — a documented simplification
   ("NilPy's unit scope is FLAT ... a leading dot adds no information to
   resolve"), which is true within one file and false the moment the same file
   is also reachable dotted.
2. `parser.inc:~33385` dedupes compiled units on `guardIdx`, derived from the
   NAME. `sub` and `pkg_sub` are different keys, so the file is compiled twice.
3. `parser.inc:33489` — the sibling probe that resolves the relative spelling
   only tries `<CurUnitDir>/<name>.py` and `.npy`, **never
   `<CurUnitDir>/<name>/__init__.py`**. Hence symptom 2. Note
   `PyTryPackageSource` already knows the `__init__` form perfectly well; it is
   just called with `SourceFileDir`, `''` and the `-Fu` roots (`:33534`) and
   **not** with `CurUnitDir`.

So the resolver is not missing the concept of a package directory — measured:
the absolute dotted form resolves one fine. The relative path simply never
reaches that probe, and when it does resolve it registers under a second name.

## Why Track A, and why it was not attempted under N

The Track N half (`pyparser.inc`) can be made to compose a dotted name only if
the current module's own dotted identity is recoverable, and it is not: unit
names are mangled (`pkg_sub` is ambiguous between package `pkg_sub` and module
`sub` in package `pkg`), and no per-unit record of the unmangled path exists.
Deriving one from `CurUnitDir` relative to `SourceFileDir` breaks under `-Fu`,
where the package root is a `PasUnitDir` instead. That is guessing, so it was
not done.

**The honest fix is that a module's identity should be its RESOLVED FILE**, not
a string spelling of how it was reached — which makes both symptoms disappear
and deletes the ambiguity rather than adding a case
(`devdocs/dev/normalise-dont-special-case.md`). That is a change to unit
identity and the dedupe key, i.e. Track A ground.

Two directions, not chosen here:

- **dedupe on the resolved path** (canonicalised) alongside the name key — fixes
  symptom 1 directly and leaves naming alone. Note `guardIdx` already has
  precedent for a second key space: the `@cpath:` key for path-form C units.
- **give each unit its unmangled dotted identity** at load, so the relative form
  can compose against it — fixes both, more invasive.

Symptom 2 additionally needs `CurUnitDir` added to the `PyTryPackageSource`
probe roots, which is small and independent of the identity question.

## Gate

`make compiler/pascal26` + both repros above, then `tools/gate.sh quick`
**before committing** so the FPC seed canary runs.

**The regression test must assert the COUNT, not the value** — `5 5` would have
passed forever. The shape that catches this class: a module that appends to a
list on import, with the importer asserting length 1 after importing it by both
spellings. Add an `isinstance`-across-spellings assertion too; that is what
catches a partial fix that dedupes the body but not the class rows.

Track N will add the `.npy` coverage on its side once this lands — the frontend
half of the test belongs with the N ticket
[[bug-n-a-subpackage-directory-does-not-resolve-as-a-module]], which is parked
blocked on this.

## Sibling check — "a translation unit compiles twice" is a recurring class here

Grepped for the sibling before filing, per
`normalise-dont-special-case.md`. Two C-frontend tickets have the same
*symptom*: [[bug-c-header-with-a-body-compiles-twice-across-the-macro-reset]]
and [[bug-c-string-h-compiles-stdlib-c-twice]].

**They are NOT the same root** — those are include-guard visibility lost across
a preprocessor macro-table reset, not unit-identity keying — so this ticket does
not subsume them and fixing one will not fix the other. Recorded because the
shared symptom makes them look like duplicates, and because three tickets in one
repo about a compilation unit being processed twice is worth someone asking
whether "how many times has this file been compiled" deserves one answer rather
than three mechanisms. Not proposed here; noted.

**Escalated 2026-08-17** as [[decide-one-answer-to-have-i-already-compiled-this-unit]]
(Track U) — three mechanisms for one concept crosses
`root-cause-over-microfix.md`'s own "three is a design flaw" threshold, so it is
a design call for the user rather than something a worker settles in passing.
**This ticket is NOT blocked on that decision** and should be fixed regardless;
the decision only governs whether the fix stays narrow or begins a unification.
