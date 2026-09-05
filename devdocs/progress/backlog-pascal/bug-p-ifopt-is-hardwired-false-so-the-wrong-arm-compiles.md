---
track: P
prio: 45
type: bug
blocked-by: []
summary: "{$IFOPT X+} evaluates to False for EVERY letter -- `cond := False { compiler option switches are not modelled }` in ProcessPasDirective -- so the wrong arm of a conditional compiles, silently, with no diagnostic. The comment is stale: pxx models R, Q, I and C and holds their state in the same procedure; those four are FIXED. What stays open is the letters pxx has no variable for but whose BEHAVIOUR is fixed -- measured against fpc 3.2.2, its IFOPT defaults ON for I, G, J, X and Z, and pxx answers False for all five, so a `{$IFOPT X+}` guarding extended-syntax code takes the else arm on a compiler that HAS extended syntax. Each remaining letter needs its own measured behavioural claim, which is why they are not in the same fix."
---

# {$IFOPT X+} is hardwired False, so the wrong arm compiles

`{$IFOPT}` is a CONDITIONAL. Getting it wrong does not produce a diagnostic —
it compiles the other branch. That is the same class as
[[bug-p-macpas-conditional-directives-are-ignored-so-both-arms-compile]] and it
is worse than a mis-set switch, because nothing downstream can tell that a
branch was chosen rather than written.

Found by censusing fpc 3.2.2's own sources for directive VALUES rather than
NAMES (the unknown-directive warning keys on the name, so a known directive
with an unhandled value is invisible to it — see
[[bug-p-a-spurious-unknown-directive-warning-cannot-fail-any-test-we-have]]).
`{$IFOPT}` is 139 uses there.

## What was fixed, and why the rest was not

`ProcessPasDirective` said

    if CaseEqual(command, 'ifopt') then
      cond := False { compiler option switches are not modelled; branch off }

and the comment was stale — `RChecksVal`, `QChecksVal`, `IChecksVal` and
`AssertionsVal` are set a few lines below it, in the same procedure. Those four
now answer from their own state. They are also where the corpus is: `{$IFOPT
R+}` alone is 113 of the 139 uses.

**`{$IFOPT R+}` was RIGHT BEFORE THE FIX, by coincidence** — fpc's R defaults
off, and "always False" agrees with "off". The uses that dominate the corpus
are exactly the ones a broken implementation gets right, which is why this
survived: the discriminating case is `{$R+}` followed by `{$IFOPT R+}`, where
fpc says TRUE and pxx said FALSE.

## The open part: letters with no variable but a fixed behaviour

Measured against fpc 3.2.2 on x86-64, 2026-09-05 — one probe per letter for the
default, one for whether an explicit `{$L+}` moves it:

| | default ON | default OFF | not tracked by fpc at all |
|---|---|---|---|
| letters | I G J X Z | R Q C B D H M P S T V | A L O |

`A` not being tracked is the useful negative: it is a NUMERIC switch, so
`{$IFOPT A+}` is false however `{$A8}` was set. Modelling it from
`PackRecordsVal` would have been wrong, and only the measurement says so.

pxx answers False for every letter, so it is wrong by default for the five in
the first column. `{$IFOPT X+}` guarding extended-syntax code takes the else arm
on a compiler that has extended syntax.

Each of those needs its own claim — *does pxx behave as `X+`?* — and that is a
per-letter determination about this compiler, not a lookup in fpc's table. Two
that are not obvious: `H` (ansistrings) is mode-dependent in fpc, and `G` (286
code generation) is a switch whose subject no longer exists.

## Where pxx will DIFFER from fpc on purpose

`{$IFOPT C+}` answers TRUE by default here and FALSE in fpc, because
`AssertionsVal` defaults ON — a decision already recorded at its declaration in
`defs.inc` (flipping it to fpc's default would turn every existing pxx assertion
into dead code silently). IFOPT reports **this compiler's** state truthfully;
matching fpc's answer would mean lying about ours.

## Not part of this, deliberately

fpc diagnoses a malformed `{$IFOPT}` — `{$IFOPT R}` and `{$IFOPT R*}` are
*Wrong switch toggle*, `{$IFOPT RR+}` and `{$IFOPT 9+}` are *Illegal compiler
switch* — and pxx silently answers False for all of them. Us accepting what fpc
rejects is not a defect, and a differing diagnostic is deferred; recorded so the
next reader does not have to re-measure it. The letter IS case-insensitive in
fpc (`{$IFOPT r+}` works), which the fix does honour.
