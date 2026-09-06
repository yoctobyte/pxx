---
slug: compat-p-nine-builtin-type-names-cannot-be-redeclared-at-all
title: "Nine builtin type names cannot be redeclared, because they lex as keywords"
track: P
prio: 30
type: compat
status: open
owner: ""
created: 2026-09-06
blocked-by: []
summary: "`type Integer = Int64;` does not COMPILE -- `expected 'begin' before 'Integer'` -- because Integer lexes as tkInteger_T and the type-declaration parser wants an identifier. fpc 3.2.2 accepts it and honours it everywhere: the declaration, a variable of that type, and a cast all answer 8. Measured 2026-09-06 over the whole population derived from paslexer.inc rather than hand-picked: TEN names lex as type keywords, and NINE of them are refused by pxx and accepted by fpc -- boolean, byte, char, double, extended, integer, longword, real, single. `string` is refused by BOTH, so it is a genuine reserved word and the boundary is exact. The control that names the cause: longint, cardinal, word and uint8 are builtin type names too and pxx redeclares all four happily, so this is not about shadowing a builtin -- it is about the name never reaching the parser as an identifier. THE DECLARATION HALF MUST NOT BE FIXED ALONE. Every USE of the name still lexes as a keyword and takes a keyword arm that never consults FindTypeAlias, so a parser that merely accepted the declaration would give a type declaration that silently does not apply -- the declared-invariant-that-never-runs shape this tree refuses everywhere else. The whole fix is that the keyword arms consult the same resolver the identifier arms do, which is [[refactor-p-five-dispatch-sites-for-one-named-type-cast]]'s ordering rule applied to the one population that cannot express it."
---

# Nine builtin type names cannot be redeclared, because they lex as keywords

## Repro

    program rd;
    {$mode objfpc}{$H+}
    type
      Integer = Int64;
    var v: Integer;
    begin
      v := 1; writeln(SizeOf(v));
    end.

    pxx:  pascal26:4: error: expected 'begin' before 'Integer'
    fpc:  8

fpc honours it at every door — `SizeOf(Integer)`, `SizeOf(v)` and
`SizeOf(Integer(1))` all answer 8.

## The population, derived rather than guessed

Ten names map to a `_T` token in `paslexer.inc`. Every one of them, plus four
builtin type names that do NOT lex as keywords, asked in both compilers:

| name | pxx | fpc |
| --- | --- | --- |
| boolean, byte, char, double, extended, integer, longword, real, single | **REFUSE** | accept |
| string | REFUSE | REFUSE |
| longint, cardinal, word, uint8 | accept | accept |

Two controls, and they are what make the row set say something:

- **`string` is refused by both.** So the sweep is not "fpc accepts everything";
  there is a real reserved word in the population and both compilers agree on it.
- **`longint`, `cardinal`, `word`, `uint8` are accepted by both.** These are
  builtin type names as much as `integer` is, and pxx lets you redeclare all
  four. So the cause is not "we protect builtins" — it is that the other nine
  never arrive at the type-declaration parser as an identifier.

`longint` is the sharpest of the four: it is a SYNONYM of `integer` with the
same width and the same meaning, and the two answer differently. Nothing about
the type system distinguishes them; only the lexer does.

## Why the obvious fix is the wrong one

Accepting the declaration is a two-line change and it would be worse than the
refusal. Every USE of `Integer` still lexes as `tkInteger_T` and lands in a
keyword arm — four of them in `ParseFactorCore` alone — and none of those arms
consults `FindTypeAlias`. So the program would compile, the declaration would
be recorded, and `v: Integer` would quietly be the builtin: **a type
declaration that silently does not apply**, which is the same shape as a
management operator that never runs and is refused everywhere else in this tree
for the same reason.

The whole fix is that the keyword arms ask the same resolver the identifier
arms ask, in the same order — source declaration first, builtin second. That is
exactly [[refactor-p-five-dispatch-sites-for-one-named-type-cast]]'s ordering
rule, and this is the one population where the rule cannot currently be
expressed at all. Whoever takes that refactor should take this with it; landing
it separately means landing it twice.

## How much real code wants this

`type Integer = LongInt;` and `type Real = Double;` are the portability-unit
idiom — a compat header that pins a width the dialect leaves open. That is the
demand, and it is a compat claim, not a bug claim: nothing pxx compiles today
produces a wrong value because of this. It refuses to compile, loudly, which is
the correct failure direction while the resolver is not shared.

## Gate

`make compiler/pascal26` + a fixture declaring each of the nine and asserting
`SizeOf` of the name, a variable of it, and a cast to it, diffed against fpc
3.2.2 — all three must move together, because two of the three moving is the
silent-declaration failure above. Keep `string` in the fixture as the row that
must stay refused.
