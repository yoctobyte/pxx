---
track: A
prio: 60
type: refactor
blocked-by: []
summary: "Generalise CompiledUnitFile[] from the .py arm to every load: one resolved-file identity answers 'have I already compiled this unit?', retiring the @cpath: key space. Decided 2026-08-19 (option B). The mechanism already exists — option A built it for one arm in 030ce07ea — so this is promoting a built thing to the general rule, not new machinery. Hazard: CompiledUnitFile is -1 when unresolved and -1 = -1, so a naive compare makes every unresolved unit identical."
status: working
owner: frank3
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

## 2026-08-20 — RAISED 45 -> 60: it now blocks a landed feature, and it answers WRONG, silently

Two new facts arrived from Track C (frank2, §3 of
[[feature-c-import-a-pascal-unit-under-a-mangled-name]]), measured on pin v367.

**1. It produces a silent wrong ANSWER, not just duplicate work.** With `r1/math.pas` and
`r2/math.pas` both declaring `unit math`, the second `#include` is a **silent no-op** —
`CompiledUnits` is keyed on the unit NAME, so the loader returns without ever reading
`r2`. The author asked for `r2`'s `Twice(21)` = 63 and got `r1`'s = **42, with no
diagnostic**. A routine present only in `r2` does not even resolve wrong; it falls through
to the crtl warning and dies at link.

That moves this out of "three mechanisms for one concept, worth tidying" and into the
repo's own escape rule: **a wrong value with no diagnostic is a bug, not a refactor.** The
slug stays `refactor-` because the fix is still the decided generalisation, but rank it as
the bug it produces.

**2. It blocks work that is otherwise finished.** §3 of the C mangled-name feature
specified resolving a collision by letting the path into the mangled name
(`path_math_pas_Sqrt`). That is **not implementable from Track C**, and the reason is this
ticket: the two units never coexist, so a path-qualified name would denote a unit nobody
loaded. Track C landed the honest half — a refusal naming both files, keyed on the
resolved path through `NormalizePath` so the same file twice (including a `./`-differing
spelling) stays allowed — which **refuses** the collision without **resolving** it.
Resolution waits here.

Track C measured before building and did not reach into `parser.inc`. Correct call.

**Sequencing, unchanged and now load-bearing:** `parser.inc` is shared A/P ground and this
is a sole-A job. As of this writing frank3 holds that file for the `ParseFactorCore` carve,
and [[feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit]] is queued
behind it too. Claim through the coordinator.

## RESOLVED 2026-08-20 (frank3) — option B, generalised, plus one Track C follow-on edit

### What landed

| site | change |
| --- | --- |
| `defs.inc` | new `CompiledUnitKey[]` — the IDENTITY an entry dedupes on |
| `parser.inc` guard key | path forms key on `@path:<NormalizePath'd resolved path>`; the `@cpath:` key space (`.c`/`.h` only, raw path TEXT) is gone |
| `parser.inc` already-compiled scan | reads `CompiledUnitKey[i]`, not `CompiledUnits[i]` |
| `parser.inc` dedupe arm | `if isPyUnit` -> `if Length(path) > 0`: EVERY load that resolved to a file, with `(CompiledUnitFile[i] >= 0)` guarding the sentinel |
| `parser.inc` alias | registered only when `CompiledUnits[dupIdx] <> strIdx` — a name aliased to itself wastes a `MAX_UNIT_ALIASES` slot whose exhaustion is an `Error` |
| `cparser.inc` `CCheckPascalUnitCollision` | scans EVERY entry of the name instead of the last one (see below) |

**`CompiledUnits[]` still means the unit NAME.** That is why the split into
`CompiledUnitKey[]` was necessary rather than tidy: `cparser.inc` reads it as a name for
the mangled-name collision check, and the scope-rank scan reads it as a name too. Keying
identity into the same array would have made it lie for every path form.

### The reading taken, and why — the third one

The ticket's one line ("consult it beside `guardIdx`") admits two readings: (i) file
identity as an EXTRA dedupe on top of name keying, (ii) file identity REPLACING it. Read
`cparser.inc` before choosing and found a third that is neither: **name forms keep the
name key; PATH forms key on the resolved file.** A bare `uses math` cannot say which file
it means until the `-Fu` search runs, so name-keying it is not a compromise, it is the
only information available; a path form always can, and that is precisely the case where
the name key was wrong.

Reading (i) would have left Track C's `r1/math` vs `r2/math` wrong value in place. It does
not survive here: both units now genuinely load.

### The consequence that had to be measured, not reasoned

Two same-named Pascal units **coexist** now. That was hazard (b) in the pre-work note and
it fired exactly as predicted: `c_pasunit_collide_fail` went from a clean refusal to
**exit 0 answering 63** (a duplicate-definition warning, the later body winning) where it
had answered 42. `CCheckPascalUnitCollision` took the LAST entry of the name, which was
now the just-registered second unit, compared its file against itself, and read the
collision as "the same file included twice".

Fixed by scanning every entry of the name. The refusal is still the right answer — the
mangled name `mymod_pas_Twice` cannot say WHICH `mymod` — so the diagnostic's text was
updated to say that, instead of the now-false "the second include would be silently
ignored".

**Cross-lane touch, flagged:** `cparser.inc` is Track C's file. The edit is 6 lines in one
procedure, forced by an A-lane change, and the alternative was landing A red. Reported to
the coordinator.

**What it un-blocks:** §3 of [[feature-c-import-a-pascal-unit-under-a-mangled-name]] was
recorded as "not implementable from Track C" because the two units could not coexist. They
can now. Path-qualified mangling is a Track C question again, not a Track A blocker. The
wrong-value symptom itself is *refused*, still not *resolved* — that half is Track C's.

### Verified (binary: self-hosted fixedpoint at this commit's tree)

- `make compiler/pascal26` — converged, byte-identical
- C path-form units: `c_pasunit` 42/7 · `c_pasunit_ovl` 9.25 · `c_pasunit_twice` 42 (the
  same file spelled with and without `./` — one unit, the two-spelling case this ticket is
  about) · all six `c_pasunit_*_fail` refusals fire with the messages the Makefile greps
- two-spelling `.py` import: the six cpyext jobs green with their Makefile expectations
  (hello 42, args/errors, containers, markupsafe, errformat, cython), plus both negative
  tests
- `tools/gate.sh quick` GREEN

### Left open

The comparison is on path TEXT. Two roots reaching one file by genuinely different routes
— a symlink, two `-Fu` roots onto one tree — are still two identities. Stated in the code
comment rather than fixed: it needs inode identity, which is a separate decision.
