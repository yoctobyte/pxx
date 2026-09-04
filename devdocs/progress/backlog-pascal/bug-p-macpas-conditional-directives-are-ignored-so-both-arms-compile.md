---
track: P
prio: 40
type: bug
blocked-by: []
summary: "The MacPas conditional family — `{$setc}` `{$ifc}` `{$elsec}` `{$elifc}` `{$endc}` `{$definec}` `{$undefc}` — is unrecognised, so every one is ignored and BOTH arms of the conditional are compiled. Measured against fpc 3.2.2 `-Mmacpas`, which takes the correct arm. Since 2026-09-04 each ignored directive at least WARNS, so it is no longer silent, but the program compiled is still not the one written."
---

# MacPas conditional directives are ignored, so both arms compile

```pascal
program mp;
{$setc TARGET_X := 1}
{$ifc TARGET_X = 0}
  {$error this arm must not compile}
{$elsec}
{$endc}
begin writeln('mp ok'); end.
```

`fpc -Mmacpas` compiles this and prints `mp ok`. pxx warns twice about unknown
directives and then **reports the error inside the arm it should never have
entered**.

## Population

Directive words in fpc 3.2.2's own sources that pxx does not recognise, by
occurrence — this family is the whole top of that list:

| directive | occurrences |
| --- | --- |
| `setc` | 31549 |
| `ifc` | 6200 |
| `endc` | 6197 |
| `elsec` | 3682 |
| `elifc` | 1625 |
| `definec` | 237 |

Concentrated in the MacOS bindings (`univint`), which is also the code most
likely to be ported. Nothing else in that census exceeds single digits once the
string-literal artefacts are removed — FPC builds directive text by
concatenation in places (`'{$ifde'+'f ...'`), which a raw grep reports as a
directive word `ifde`; those are not real and are not counted here.

## Why "it warns now" is not enough

Compiling both arms is a wrong-program outcome, not a diagnostic gap. It happens
to fail loudly when the dead arm contains something invalid (as above), and that
is luck: two arms that are each independently valid — the common case for a
`{$ifc}` selecting between two constant definitions — compile into a duplicate
definition or a silently wrong constant.

## The fork

Either implement the family (it is `{$ifdef}`/`{$if}` machinery under different
spellings, and `{$setc}`/`{$definec}` are `{$define}` with a value, which
`PasDefineValue` already carries), or make an unhandled *conditional* directive
a hard **error** rather than a warning — the same reasoning that made an
unfindable include a hard error in `bug-pascal-include-search-silent-miss`.
Ignoring a conditional is categorically different from ignoring a switch: a
switch changes how code is compiled, a conditional changes *which* code is.

Found by censusing fpc's corpus for directive words this compiler calls unknown,
after the unknown-directive warning landed — the census that also found `{$A n}`
being reported as a typo.
