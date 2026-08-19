---
track: A
prio: 45
type: refactor
blocked-by: []
summary: "Generalise CompiledUnitFile[] from the .py arm to every load: one resolved-file identity answers 'have I already compiled this unit?', retiring the @cpath: key space. Decided 2026-08-19 (option B). The mechanism already exists — option A built it for one arm in 030ce07ea — so this is promoting a built thing to the general rule, not new machinery. Hazard: CompiledUnitFile is -1 when unresolved and -1 = -1, so a naive compare makes every unresolved unit identical."
---

# One resolved-file identity for a translation unit

- **Track A** — `compiler/parser.inc` (`ParseUsesUnit`) + `compiler/defs.inc`. Shared A/P
  ground, so **sole-A job**: must not be edited concurrently with Track P.
- **Decision:** [[decide-one-answer-to-have-i-already-compiled-this-unit]], option B,
  decided by the user 2026-08-19. Read that ticket for the fork and the reasoning; this
  one is the work.

## Why

Three unrelated mechanisms answered "have I already compiled this translation unit?" —
two of them are the same question and unify:

| mechanism | keys on | status |
| --- | --- | --- |
| `CompiledUnits[]` / `guardIdx` | the unit **NAME** | absorbed by this ticket |
| `@cpath:` key space | the path **TEXT** | absorbed by this ticket |
| a crtl header carrying function BODIES | not identity at all | **NOT this concept** — see below |

`@cpath:` exists because unit-NAME keying collided for path-form C units
(`uses './x.c'`); `CompiledUnitFile[]` exists because it collided again for `.py` modules
reached by two spellings. That is a key space added per surprise, which is the pattern
`devdocs/dev/root-cause-over-microfix.md` says to stop repeating. One resolved-file
identity deletes cases instead of adding them.

## The mechanism is already built — for one arm

Option A landed it on 2026-08-17 (`030ce07ea`) while fixing
[[bug-a-a-python-module-s-identity-is-its-name-not-its-file]]:

| site | what |
| --- | --- |
| `compiler/defs.inc:2288` | `CompiledUnitFile : array[0..255] of Integer;` |
| `compiler/parser.inc:33942` | `CompiledUnitFile[...] := -1;  { filled in once resolved }` |
| `compiler/parser.inc:34590` | `if CompiledUnitFile[i] = pyFileIdx then pyDupIdx := i;` — **the .py arm only** |
| `compiler/parser.inc:34616` | `CompiledUnitFile[savedCUC] := pyFileIdx;` |

So this ticket is **promotion, not invention**: populate `CompiledUnitFile` for every load
that resolves to a file, consult it in the already-compiled scan at `parser.inc:33898`
beside `guardIdx`, and retire the `@cpath:` special case at `:33854` into it.

## THE HAZARD — the sentinel collides, and it will pass every test

`CompiledUnitFile` is **`-1`** for any entry not resolved to a file, and `-1 = -1`. A
generalised comparison therefore makes **every unresolved unit identical to every other**,
so the second ambient/builtin unit is skipped as already-compiled.

Skip `-1` explicitly in the scan. This will not show up in the suite — it surfaces much
later as a builtin silently not loading, far from the commit that caused it.

## Explicitly OUT of scope — the C preprocessor half

[[bug-c-header-with-a-body-compiles-twice-across-the-macro-reset]] (and the resolved
`bug-c-string-h-compiles-stdlib-c-twice`) look like this and are a **different root** —
and note that ticket's TITLE is superseded by its own body. Measured 2026-08-16: carrying
the macro table changes nothing (byte-identical output), and forcing the guard on makes
the pull fail to compile, because the pulled region needs stdarg.h's declarations and a
guard is all-or-nothing.

The actual cause is that `lib/crtl/include/stdarg.h` carries six `static` function
**BODIES** and the crtl auto-pull must include it. The fix is moving them to
`lib/crtl/src/stdarg.c` — **Track C library work**, nothing to do with unit identity or
the preprocessor.

Do not pull them in. The decision recorded this as option C precisely so the resemblance
stops costing people time — the symptom is shared, the root is not, and that was checked
twice rather than assumed.

## Gate

`make compiler/pascal26` (IS the self-host fixedpoint) + a repro exercising both a
path-form C unit and a two-spelling `.py` import + `tools/gate.sh quick`. Push.

**Land the general rule and the `-1` guard in ONE commit.** A half-applied change to the
load path is the CRITICAL case `tools/progress.sh check` fails on, and every lane's gate
runs through this function.
