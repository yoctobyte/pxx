---
summary: "Pascal: subclassing is half-wired — inherited fields/methods invisible unqualified, wrong Create, default property loses subscript assignment"
type: bug
track: P
prio: 60
---

# Pascal: inherited members are not usable from a subclass

- **Type:** bug (Pascal frontend / class semantics) — **Track P** (shared
  `parser.inc`/`symtab.inc` ground, so it obeys Track A's rules too)
- **Status:** backlog
- **Opened:** 2026-07-26 — hit implementing `collections.Counter` in
  `compiler/builtin/pylib.pas` ([[feature-nilpy-collections-and-string-methods]]).
  Counter shipped as a dict MODE instead of a subclass to route around this.

## Four separate failures, one theme

With `TSub = class(TBase)` where TBase has fields and methods:

1. **Inherited METHOD invisible unqualified.** Inside a TSub method, a bare call
   to TBase's `indexof(k)` → `error: undefined variable (indexof)`. `Self.indexof(k)`
   works.
2. **Inherited FIELD invisible unqualified.** Same place, `FVals` →
   `error: undefined variable (FVals)`. `Self.FVals` works.
3. **Inherited constructor resolves to the wrong Create.** With no constructor
   declared on TSub, `TSub.Create` →
   `error: not enough arguments to constructor TSub.Create (parameter start has no
   default)` — it bound some other `Create` entirely. Declaring
   `constructor Create; begin inherited Create; end;` on the subclass works.
4. **Inherited default property loses subscript ASSIGNMENT.** Re-declaring
   `property Items[...] read fetch write store; default;` on the subclass still
   left `c[k] = v` failing to parse from NilPy
   (`error: expected expression`), while the same expression on the base class
   parses. Read access worked.

## Not reproducible in a standalone program

A minimal program — base with `function idx`, subclass calling it bare, via
`Self.`, and via `inherited` — compiles and prints correctly for all three forms.
So the failure needs whatever pylib does differently: a large `public` member
list, a unit rather than a program, `const Variant` parameters, a method that
OVERRIDES a same-named parent method (Counter re-declared `fetch`), or a
combination. Reproducing that minimally is the first task here.

## Why it matters beyond Counter

Subclassing a library class is ordinary Pascal and ordinary Python. Until this
works, every pylib type that wants a specialised variant has to be a mode flag on
the parent (what Counter did) or a copy. It also blocks the natural shape for
[[feature-nilpy-configparser]], whose `optionxform` override is exactly a subclass
overriding a parent method.

## Gate

`make test` + self-host byte-identical, plus a `test/` case covering all four
shapes above. NilPy side: `make test-nilpy` with a `.npy` subclassing a pylib type
and using `c[k] = v`.
