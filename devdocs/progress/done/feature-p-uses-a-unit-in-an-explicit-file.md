---
track: P
prio: 55
type: feature
blocked-by: []
summary: "DONE 2026-09-04. `uses mymod in 'mymod.pas';` parses and works, including the BARE file name every generated .dpr writes -- resolved against the directory of the file holding the clause, which is FPC's rule and is what `./` already means to pxx's loader. Implemented by reusing the quoted-path loader and then wiring the DECLARED name to it, so `in` needs no second file-finding path; when the basename already equals the declared name (the only shape FPC permits at all) the two intern to one slot and the alias row is a no-op. Byte-identical to FPC 3.2.2 on the test's three shapes. NOT asserted: a declared name differing from the unit's own -- pxx accepts it, FPC's rule there is a DOS-era 8-character tolerance measured directly (SomeName accepted, SomeNameXX rejected, exact name accepted, one unchanged file), and pinning us to a length artifact would be pinning us to the wrong thing."
status: done
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


## Resolution 2026-09-04 (frankD, Track P)

`ParseUsesEntry` grows an `in` arm beside the existing `as` arm. The file is
loaded through the **quoted-path form that already worked**, and then the
declared name is wired to whatever the loader registered — so there is no
second file-finding path to keep in step with the first, which is the failure
mode `normalise-dont-special-case.md` describes.

```
uses mymod in 'mymod.pas'    binds `mymod`, the unit's own declared name
uses './mymod.pas' as m      binds `m`, an alias
```

When the file's basename already equals the declared name the two intern to the
same slot and the alias row is skipped as a no-op. That is not an optimisation:
it is **the only shape FPC permits at all**, so it is the shape all real input
takes.

### The bare file name is the whole feature, and it is one line

`uses Unit1 in 'Unit1.pas'` — no separator — is what every generated `.dpr`
writes, and it is the form the ticket's measured symptom was really about. FPC
resolves it against the directory of the file holding the clause; pxx's loader
already means exactly that by a leading `./`, because relative paths there are
taken against `CurUnitDir` (`SourceFileDir` for the program, the unit's own
directory for a nested one). Without the prefix the loader reads the string as
a unit NAME containing a dot and reports `unit source not found: mymod.pas`.

Only when there is no separator: an author who wrote `in 'sub/other.pas'`
already has a path, and prefixing an absolute one would be wrong. **A backslash
is deliberately not treated as a separator** — Delphi sources write
`in '..\shared\Foo.pas'` and pxx's existing quoted-path form does not accept
that either, so it is one question about Windows path spelling across both
spellings rather than something to answer twice, differently, here.

### What is asserted against FPC, and what is deliberately not

`test/test_uses_in_explicit_file.pas` (+ three helper units) runs three entries
in one clause — bare name, path with a separator, and a qualified use of the
declared name — and prints the same two lines under pxx and FPC 3.2.2. The
qualified row is there because a flat lookup answers the first two either way
and so cannot show *which* name `in` bound.

**A declared name that differs from the unit's own is NOT asserted.** pxx
accepts it; FPC's behaviour there was measured directly rather than assumed,
on one unchanged file:

| clause name | FPC 3.2.2 |
| --- | --- |
| `A`, `Ab`, `Abc`, `SomeName` (≤ 8 chars) | accepted |
| `SomeNameXX`, `othername_i`, `DeclaredElsewhere` | `Illegal unit name` |
| `othername_in` (the unit's own name) | accepted |

That is a DOS 8.3 short-name tolerance, not a rule — and it sits on top of
FPC's more basic requirement that a unit's name match its file's name at all,
`in` or no `in`. No valid FPC source contains the shape. Us accepting what FPC
rejects is not a defect, so the behaviour is left free rather than frozen
against a length artifact.

**An earlier reading of this was wrong and is recorded because it nearly went
into the test:** a same-directory probe with the name `SomeName` matched FPC,
which I first explained as a stale `.ppu` being reused. It was not — `SomeName`
is exactly eight characters, and the probe was measuring the tolerance. The
correction came from re-running the same shape at several name LENGTHS, which
is the variation the original probe did not make.

### Tooling: the new spelling was invisible to the wiring gate

`tools/check_test_wiring.py` follows `uses` references to decide whether a
helper in `test/` is reached from a wired test, and it split a uses clause on
commas and took each entry as a bare name. `mymod_in in 'mymod_in.pas'` is not
a bare name, so all three helpers of the new test landed in
`THIS PUSH ADDS 3 TEST FILE(S) THAT NOTHING RUNS`. Exempting them in
`UNWIRED.txt` would have been the wrong fix — they ARE wired, the tool could
not see it, and every future `in` test would have hit the same wall.

The checker now takes **both halves of every entry**: each bare identifier and
the basename of each quoted path. That covers `in '<file>'`, pxx's
`'<path>' as <alias>`, and the cross-language `'./lib2.c' as c` in one pass.
Positive-controlled: a planted unwired test is still reported, the scanned
population is unchanged at 3411, the parked and advisory rows are identical,
and both of the checker's own devtests pass.
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d87b2f0fb.
