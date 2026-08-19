---
track: P
prio: 30
type: feature
blocked-by: []
summary: "`uses mymod in 'mymod.pas';` — the FPC/Delphi spelling for naming a unit's source file — does not parse. pxx has the quoted-path form (`uses './mymod.pas' as m;`, shipped 2026-06-30) but not the standard `in` one, so ordinary FPC project sources are refused at the uses clause."
---

# `uses <unit> in '<file>'` — the standard Delphi/FPC spelling

**Filed 2026-08-19 at the user's direction, explicitly LOWER priority than the NilPy import
work it was found beside.** *"We totally overlooked the `uses .. in` syntax, even when we
were talking about `uses .. as`. That's also worth doing, but lower prio."*

## Measured, on pin v361

    uses mymod in 'mymod.pas';   ->  parse error at `in`
    uses './mymod.pas' as m;     ->  works  (m.Twice(21) = 42)
    uses './lib2.c'    as c;     ->  works  (cross-language)

So pxx has **a** way to name a unit's file and it is not the standard one. `in` is what FPC
and Delphi write, and it is what appears in every real `.dpr` / project source — so a corpus
program using it is refused at its uses clause, before any semantics are reached.

## Why it is a `compat` item and not just a nicety

This is squarely reference-compatibility: the default is to behave like FPC, and `in` is not
an obscure corner — it is how Delphi projects have named unit files for thirty years. It is
also the one place the two spellings differ in *meaning*, which is the interesting part:

| spelling | binds the name | reaches foreign symbols |
| --- | --- | --- |
| `uses mymod in 'mymod.pas';` (FPC) | `mymod`, unqualified — the unit's own name | n/a, same language |
| `uses './mymod.pas' as m;` (pxx) | `m`, an alias | yes — the alias maps to the REAL unit's `Strs[]` index |

So `in` should bind the unit under **its declared name**, not an alias, and the existing
alias machinery is not automatically the right implementation. See
`decided/decide-cross-language-qualifier-syntax` for why the alias form resolves foreign
symbols the way it does — that reasoning is about the alias, and `in` is not one.

## Scope note

`in` is a *within-language* file selector: it says where a Pascal unit lives, not what
language it is. It is therefore **not** an alternative to
[[feature-a-a-bare-nilpy-import-means-python-and-another-language-needs-its-extension]] and
does not satisfy that ticket's rule 2. Two different jobs that happen to look alike.

## Gate

Track P's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. The Pascal frontend
lives in the shared `lexer.inc`/`parser.inc`, so it obeys A's no-concurrent-edit rule.

## Log
- 2026-08-19 — filed, deliberately low prio per the user.

## Triage 2026-08-19 (Track D re-triage pass, pin **v364** — after the import/uses refactor landed)

**Genuine feature, still wanted — and specifically NOT settled by the refactor
it sits next to.** Re-measured against v364 rather than the v361 the ticket
quotes, because that work changed how units are named:

```
uses mymod in 'mymod.pas';   ->  pascal26:2: error: unexpected token  (near `in`)
uses './mymod.pas' as m;     ->  works, m.Twice(21) = 42
```

Unchanged on both rows. The quoted-path form still works and the standard
Delphi/FPC spelling still does not parse, so the compat gap the ticket
describes survived the refactor intact. Its central design point stands too:
`in` must bind the unit under **its declared name**, not as an alias, so the
existing alias machinery is not automatically the implementation.
