---
track: A
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
found-by: frankB
summary: "`compiler/compiler.pas:10` is `{$CASESENSITIVE ON}`, and fpc has no such directive -- it warns `Illegal compiler directive` and ignores it. So a pair of identifiers in our own source differing only in case is TWO names to pxx and ONE to the fpc seed, and the seed's local SHADOWS the global. 21 such pairs measured (PXXDBG=a.casedup over compiler.pas, 2026-09-06); `pyImportLang` in ParseUsesUnitBody is one, and it reads the global on the self-hosted compiler and an uninitialised local on the seed. Bootstrap still converges because compiler.pas contains no NilPy import, so the divergent value is '' either way -- that is luck, not a property. Same class as the seed-drift forward-decl lint the gate already runs, for a VARIABLE rather than a routine."
---

# The compiler's own source means two different things to fpc and to pxx

Measured 2026-09-06 at compiler `bb002bffcb5c`.

```pascal
program cs2;
{$CASESENSITIVE ON}
var PyImportLang: AnsiString;
procedure P; var pyImportLang: AnsiString;
begin pyImportLang := PyImportLang; PyImportLang := ''; ... end;
```

    fpc 3.2.2   Warning: Illegal compiler directive "$CASESENSITIVE"
                local=""    global="pas"      { one name; the local shadows }
    pxx         local="pas" global=""         { two names }

`compiler/pasparser_proc.inc:4471` is exactly that shape and is not a reduction:
a local `pyImportLang` claims the global `PyImportLang` and clears it. Under pxx
that is the intended claim-and-clear. Under the fpc seed both spellings are the
local, so the global is never claimed and never cleared and an explicit import
language leaks into the next import.

## Why nothing has failed

`compiler.pas` has no NilPy import, so `PyImportLang` is `''` on both readings
and the bootstrap converges. Every other pair of the 21 is a local shadowing a
global where the routine only ever spells one of the two, so both readings agree
by accident of usage rather than by construction.

## The census, and the instrument

`PXXDBG=a.casedup` (added the same day) reports every case-only pair at its
declaration. Over `compiler/compiler.pas`: **21 pairs, all `samescope=0`** --
`code`/`Code` nine times, `fixCount`/`FixCount` four, `frameSize`, `astTk`,
`curBlockId`, `symBlockId`, `dynamicOff`, `dynamicSize`, `N`/`n`,
`pyImportLang`. Zero same-scope duplicates, which is the good news.

The check that would hold this closed is a lint, not a compiler change: no two
identifiers in `compiler/**` differing only in case. It belongs beside the
existing FPC-seed forward-decl lint in `tools/gate.sh`, which exists for the
identical reason -- `paslexer.inc:463` calling `LowerCase` before we declare it
resolves to FPC's OWN system-unit routine, and the gate's note already says the
seed build and the self-hosted build run different implementations there.

## Neighbour

[[bug-p-a-parameter-and-a-local-that-differ-only-in-case-are-two-symbols]] is
the same collision INSIDE one scope, where fpc refuses the file outright. This
one is across scopes, where fpc accepts it and means something else.

## A census that reports ZERO is conditioned on the input reaching the site

*(frankA, 2026-09-06 — recorded here at frankB's request, because the instrument
this ticket ships is the one it bites.)*

`a.casebind` and `a.casedup` are delta instruments: their null output is a
**number**. Zero is a legitimate value of that number, so it does not look like
the "nothing ran" case — it looks like an answer.

**The measured instance is frankB's.** Their first `a.casebind` run over
`test_parallel_for_private` and `test_critsec_once` reported **zero moved
bindings**, which reads as "the resolution change did not cause these". Both
fixtures need `--threadsafe`; without it the compile dies inside `palthread.pas`
before the program body is parsed, so `FindSym` never reached a single
identifier the instrument had been asked about. The instrument was correct and
answered a question nobody asked: *how many bindings moved in the part of the
compile that ran.*

**My own part in this belongs on the record accurately: I supplied the shape and
the wrong instance.** I framed it after arguing that the same census had missed
a real defect in `pasparser_proc.inc:4471`. It had not. The census was right,
the defect did not exist, and the thing I mistook for one is `{$CASESENSITIVE
ON}` — this ticket. So the section rests on frankB's measurement, not on mine.

CLAUDE.md already carries the general rule: *"a guard must also be AIMED and
READ … a comparison whose inputs were never proven to exist cannot fail."* The
wrinkle a census adds is that there is no comparison to inspect — only a count,
and the count is well-formed either way.

**The cheap fix is in the instrument, not in the discipline.** Have
`a.casebind` report the resolutions it **SAW** beside the ones that **MOVED**.
`0 of 0` and `0 of 4127` are different answers and only the second one is
evidence; today both print as zero.
