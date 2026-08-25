---
track: P
prio: 50
type: bug
blocked-by: []
summary: "A token that starts no declaration is silently skipped in a UNIT's interface/implementation section, while the identical token in a PROGRAM's declaration section is correctly rejected. A typo'd section header (`cosnt K = 5;`) therefore discards the declarations behind it with no diagnostic; the error surfaces later at the use site, or not at all. FPC rejects at the typo."
status: backlog
owner: —
---

# Stray tokens in a unit declaration section are silently skipped

- **Type:** bug (Pascal frontend — accepts-invalid, missing diagnostic)
- **Track:** P — tag: compat
- **Found:** 2026-08-25, while building the fgl rung of the Pascal real-world
  corpus ladder. Found *by accident*, which is the point: a probe that poisoned a
  vendored unit to test unit-resolution precedence still compiled clean, so the
  probe silently measured nothing.

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374; oracle FPC 3.2.2)

`uu.pas`:
```pascal
unit uu;
interface
zzz                          { <- starts no declaration }
function F: Integer;
implementation
function F: Integer; begin F := 1; end;
end.
```

| where the stray token sits | FPC 3.2.2 | pxx |
| --- | --- | --- |
| unit `interface` section | `Fatal: Syntax error, "IMPLEMENTATION" expected but "identifier ZZZ" found` | **accepted silently** |
| unit `implementation` section | rejected | **accepted silently** |
| **program** declaration section | `Fatal: Syntax error, "BEGIN" expected but "identifier ZZZ" found` | rejected: `error: unexpected token` |
| inside a procedure body | rejected | rejected: `undefined variable (ZZZ)` |

Accepted silently in the unit case for an identifier, an integer literal, and a
bare `)`. Declarations *after* the stray token are still registered — the parser
skips the offending token and carries on.

The harmful shape is a mistyped section header:

```pascal
unit uu;
interface
cosnt K = 5;                 { typo for `const` }
function F: Integer;
implementation
function F: Integer; begin F := K; end;
end.
```
- FPC: `uu.pas(3,1) Fatal: Syntax error, "IMPLEMENTATION" expected but "identifier COSNT" found` — points at the typo.
- pxx: the whole `cosnt K = 5;` is discarded, and the only complaint is
  `error: undefined variable (K)` **at the use site, in the wrong place**. Had
  nothing used `K`, the unit would have compiled clean with a declaration
  missing.

## Root shape

Program and unit declaration sections are two paths through one concept, and the
unit one has an "unrecognised token → skip it and continue" recovery the program
one does not. Normalise onto the program path's behaviour
(`devdocs/dev/normalise-dont-special-case.md`) rather than adding a diagnostic to
the recovery. Possibly related to the open note about error recovery swallowing
diagnostics (`ticket(A): error recovery silences every lowering-only diagnostic`)
— check whether that is the same mechanism before fixing either.

## Second, smaller finding in the same probe

A unit's header name is not checked against its filename: a file `uu.pas`
containing `unit notuu;` compiles and satisfies `uses uu`. FPC rejects with
`Illegal unit name`. Lower severity (it cannot silently change behaviour, only
tolerate a rename mistake) — worth folding into the same fix if the parser is
open, otherwise leave it.

## Why it matters beyond the diagnostic

This weakens every "it compiled" signal on unit-shaped corpus code. A corpus rung
whose oracle is "the unit built" cannot distinguish a unit that built from a unit
that had text quietly thrown away — which is precisely the reporting failure the
corpus ladder exists to avoid.

## Gate
`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`. Note
the fix tightens acceptance, so re-run the FPC conformance sweep
(`tools/run_pascal_conformance.sh`) before landing — some `test/*.pas` or
vendored units may be relying on the silent skip.

## Links
Found under [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]
