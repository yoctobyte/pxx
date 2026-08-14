---
track: D
prio: 50
type: doc
summary: "Write the user-facing page for cross-language name resolution: own-language-first, case must agree, warn on surviving ambiguity, qualification as the escape — plus the per-frontend default rule (CPython for .npy, FPC for .pas). The rules are decided and scattered across seven tickets and two devdocs; nothing in docs/ tells a programmer what happens when two units export the same name."
status: done
owner: claude-D
---

# Document the cross-language name-resolution rules

- **Type:** doc — **Track D** (`docs/**`, the pages the website publishes
  verbatim). Requested by the user 2026-08-14 while clearing the Track U queue.
- **Nothing to decide.** Every rule below is already settled; this is writing it
  down where a programmer will find it. Today it lives in decision tickets and
  internal dev docs, neither of which ships.

## What to document

### 1. Cross-language symbol resolution

Decided [[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]]:

1. **Own language first.** A C call to `exp` binds C's `exp`; a Pascal call to
   `Exp` binds Pascal's. They are *different functions and are allowed to be* —
   `Round(2.5)` is 2 in Pascal and 3 in C, both correct.
2. **A cross-language match must agree on case.** Every Pascal spelling is
   capitalised, every C name lowercase, so this closes the known collision class
   by itself.
3. **The compiler warns** where a genuine ambiguity survives, naming what it
   picked. It does not guess quietly.
4. **Qualification is the escape** and always works.

Worth stating plainly for the reader, because it sets expectations: a programmer
who deliberately pulls in both `math.pas` and `math.c` and then writes an
ambiguous bare call **owns that outcome**. The compiler's job is to warn.

### 2. Which reference implementation a frontend follows

The governing rule (user, 2026-08-13), currently recorded only inside
[[decide-nilpy-builtin-vs-pascal-unit-name-resolution]]:

> The default follows the **reference implementation per frontend** — CPython
> for `.npy`, FPC for `.pas` — with deviations behind `--strict-*` flags.

This is the rule a user needs most and can find least. It explains why the same
construct can legitimately resolve differently in a `.npy` and a `.pas`.

### 3. What cross-import is for

From [[decide-merge-variant-c-with-bare-name-collision]] — a scope statement
worth publishing, because it stops people asking for things that are out of
scope by design:

> Cross-import exists so a program can reach the **other language's real
> libraries** — `import sqlite.c` from Python, compiling SQLite in statically.
> Each frontend has its own runtime library. It is not a route for a `.npy` to
> pull Pascal's RTL.

### 4. Shadowing is allowed and preferred

Not a wart to apologise for: the reference implementations allow it, so pxx
does. A shadowed routine stays reachable under a qualified name.

## Where it goes

`docs/language/` already has `dialect.md`, `fpc-compatibility.md` and
`exceptions.md`; a `name-resolution.md` beside them fits, with a link from
`dialect.md`. Sections 1-2 are the substance; 3-4 can be short.

## Source material — do not re-derive it

| | |
|---|---|
| `devdocs/dev/name-resolution.md` | the internal reference; §2.1 carries the decided rule set, §2.4 the qualification escape |
| `devdocs/dev/math-implemented-twice.md` | *why* two implementations exist — read before writing that duplication is debt |
| [[decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language]] | the rule set, decided |
| [[decide-nilpy-builtin-vs-pascal-unit-name-resolution]] | the per-frontend governing rule (still open on three sub-points, none of which affect §1-3 here) |
| [[decide-merge-variant-c-with-bare-name-collision]] | the cross-import scope statement |
| [[decide-class-namespace-scoping]] | why classes are scoped per unit, and the shared-name exemption |
| [[decide-pascal-uses-campaign-scope]] | how the `uses` work was sequenced |
| [[bug-pascal-uses-is-transitive]] | the root cause behind the whole family; **still open**, so do not document `uses` as non-transitive yet |
| [[bug-p-uses-order-does-not-decide-which-unit-wins]] | done — last-in-clause wins, for ROUTINES |
| [[feature-a-own-language-first-symbol-resolution]] | Track A, unfinished; the implementation |

## One thing NOT to document yet

`uses` is still transitive ([[bug-pascal-uses-is-transitive]], p80, blocked on a
Track A landing). Describe symbol resolution, not module scoping, until that
lands — otherwise the page ships a rule the compiler does not yet enforce.

## Gate

A programmer reading only `docs/` can answer: *"I have `math.pas` and `math.c`
both in scope and I call `exp` — what happens, and how do I say which one I
meant?"* Any code sample in the page compiles against `$(PXX_STABLE)`.

## Log
- 2026-08-14 — resolved, commit 6ae11f9fc.
