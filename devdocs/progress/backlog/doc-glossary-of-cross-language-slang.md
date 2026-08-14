---
track: D
prio: 40
type: doc
summary: "pxx accepts Pascal, C and Python, so its docs mix three vocabularies and define none of them. A reader fluent in one hits the others' slang unexplained — `cls`, `self`, dunder, repr-vs-str going one way; unit, uses, RTL, pinned, fixedpoint going the other. Wanted: a glossary with a Python-to-Pascal equivalence table, since most terms have a counterpart the reader already knows."
---

# Glossary: the slang, and what it maps to in the other language

- **Type:** doc — **Track D** (`docs/**`). Requested by the user 2026-08-14,
  after `cls` turned out to be an unexplained abbreviation.
- **Nothing to decide**, and no code involved. Pure writing.

## Why this is worth a page

pxx is unusual in that one toolchain accepts Pascal, C and Nil-Python, so its
documentation inevitably mixes three vocabularies — and assumes all of them. A
Pascal programmer reading the NilPy pages meets `cls`, `self`, "dunder" and
`__name__` with no introduction; a Python programmer reading the Pascal pages
meets `unit`, `uses`, RTL, "pinned" and "fixedpoint" the same way.

The specific trigger: **`cls` is never spelled out anywhere.** It is short for
*class* — the conventional first parameter of a `@classmethod`, the class the
method was called on, as `self` is the instance. The abbreviation exists only
because `class` is a reserved word and cannot be a parameter name. Obvious once
said; invisible until then.

## The valuable part is the equivalence table, not the definitions

Most of these terms have a counterpart the reader already knows, and saying so
is worth more than a definition. Starting material:

| Python / NilPy | Pascal | note |
|---|---|---|
| `self` | `Self` | the instance |
| `cls` (in a `@classmethod`) | `Self` in a `class function` | **the class, not an instance** — and both bind to the class it was CALLED on, not the one it was defined in |
| dunder (`__init__`, `__eq__`) | constructor / operator overload | "dunder" = double underscore |
| `__name__` | `ClassName` | |
| `repr()` vs `str()` | — | no Pascal counterpart; worth explaining, since they differ for exceptions and containers |
| module | unit | |
| `import` | `uses` | but see the name-resolution page |
| duck typing | — | |

And the other direction, for a Python reader:

| Pascal / pxx | meaning |
|---|---|
| unit | a module; `interface` is its public part |
| RTL | run-time library — the standard library |
| **pinned** / **stable** | the blessed compiler binary other tracks build against |
| **fixedpoint** | the compiler compiling itself to a byte-identical binary |
| `{$IFDEF}` | conditional compilation, evaluated at compile time, **per unit** |
| shortstring / ansistring | two string representations with different semantics |

## Scope

Keep it a glossary, not a tutorial. One or two lines per term, the equivalence
where one exists, and a link to the page that treats it properly. It is a
lookup, and it should stay short enough to stay accurate.

`docs/reference/` is the natural home; link from the NilPy and Pascal landing
pages.

## Related

- [[doc-cross-language-name-resolution-rules]] — the sibling doc ticket from the
  same session. Same root cause: the rules and the vocabulary are both settled
  and both live only where a contributor would look, not where a user would.

## Gate

A Pascal programmer can read the NilPy pages, and a Python programmer the Pascal
pages, without meeting an unexplained term. Concretely: `cls` is defined, and it
says which class it binds to for an inherited method — because that is the part
that is not guessable.
