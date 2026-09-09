---
slug: compat-p-nine-builtin-type-names-cannot-be-redeclared-at-all
title: "Nine builtin type names cannot be redeclared, because they lex as keywords"
track: P
prio: 30
type: compat
status: done
owner: frankH
created: 2026-09-06
blocked-by: []
summary: "CLOSED 2026-09-09. All fourteen rows of the derived population now match fpc 3.2.2. `type Integer = Int64;` does not COMPILE -- `expected 'begin' before 'Integer'` -- because Integer lexes as tkInteger_T and the type-declaration parser wants an identifier. fpc 3.2.2 accepts it and honours it everywhere: the declaration, a variable of that type, and a cast all answer 8. Measured 2026-09-06 over the whole population derived from paslexer.inc rather than hand-picked: TEN names lex as type keywords, and NINE of them are refused by pxx and accepted by fpc -- boolean, byte, char, double, extended, integer, longword, real, single. `string` is refused by BOTH, so it is a genuine reserved word and the boundary is exact. The control that names the cause: longint, cardinal, word and uint8 are builtin type names too and pxx redeclares all four happily, so this is not about shadowing a builtin -- it is about the name never reaching the parser as an identifier. THE DECLARATION HALF MUST NOT BE FIXED ALONE. Every USE of the name still lexes as a keyword and takes a keyword arm that never consults FindTypeAlias, so a parser that merely accepted the declaration would give a type declaration that silently does not apply -- the declared-invariant-that-never-runs shape this tree refuses everywhere else. The whole fix is that the keyword arms consult the same resolver the identifier arms do, which is [[refactor-p-five-dispatch-sites-for-one-named-type-cast]]'s ordering rule applied to the one population that cannot express it."
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


## 2026-09-09 — closed, and NOT by the fix this ticket prescribed

`type Integer = Int64;` compiles and applies. All fourteen rows of the
population derived above match fpc 3.2.2: the nine refused names accept, and
`string` still refuses in BOTH compilers, so the boundary this ticket measured
is intact and is still exact.

**The prescription was "the keyword arms consult the same resolver the
identifier arms do". That was measured too expensive and, worse, the wrong
SHAPE.** The keyword-token arms number about 110 across seven files — the four
cast doors in `ParseFactorCore`, the type-kind case in `pasparser_decl.inc`,
array index types, `Str`/`Write` formatting, `TypeInfo`, generic type
arguments, and the const folder's own door 4000 lines away. Teaching each of
them to ask `FindTypeAlias` first is a rule spelled per caller, and a rule
spelled per caller fails by an ABSENT COPY: the arm nobody edited keeps meaning
the builtin, the declaration compiles, and the program silently gets the wrong
type — which is the exact failure this ticket refused the two-line fix for.

**The fix is a DEMOTION.** `TypeDeclNameTokIsIdent` (`pasparser_name.inc`)
answers the type-declaration loop's "can this token be the name", and when the
token is one of the eight redeclarable type-keyword kinds followed by `=`, it
rewrites every later token of that SPELLING in the stream to `tkIdent`. After
that the name flows the path `longint` has always flowed — alias first, builtin
second — so the declaration, a variable of the type, `SizeOf` of the name and a
cast to it move together with no arm taught anything. A token that never
arrives as a keyword needs no resolver.

**Keyed on the SPELLING, not the KIND, and that is the whole of the danger
here.** `byte` and `integer` are ONE token kind (`tkInteger_T`), so a
kind-keyed demotion hands `type Integer = Int64;` a redefined `Byte` as well:
a second type silently changing width from a declaration that never named it.
Row 8 of the fixture is that control and every other row passes while it is
broken.

**Scope, narrower than "redeclaration works".** The rewrite runs FORWARD from
the declaration to the end of the token stream — exactly declare-before-use,
and it covers a unit's consumers because a unit's tokens are spliced in ahead
of them. It does not model per-unit visibility: one stream, so the alias
reaches every later token, and a unit spliced in AFTER the declaration keeps
the builtin meaning. Nothing in the corpus writes that; if it ever bites it is
a new ticket, not a hole in this one.

`test/test_a_builtin_type_name_is_redeclared` — nine rows, fpc-identical, and
identical on i386/aarch64/arm32/riscv32 under qemu. `string`'s refusal is a
one-line check in the fixture header, because a program that must fail to
compile cannot share a file with programs that must run.

**What this does NOT close.** The keyword arms still BUILD their own cast nodes
for the names nobody redeclared, which is the recognition half of
[[refactor-p-five-dispatch-sites-for-one-named-type-cast]]. That is untouched
and is where the seven defects in one day came from.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
