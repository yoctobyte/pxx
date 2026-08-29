---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`--where` advertises PXX_HOME as tier 2, overriding the exe-dir defaults, but setting it changes nothing: units still resolve from compiler/../lib/rtl, and even REMOVING a unit from the PXX_HOME tree does not produce 'unit not found'. Found while trying to test a compiler hypothesis against a modified copy of the RTL instead of editing Track B's files."
status: backlog
owner: unassigned
---

# PXX_HOME is advertised but not honoured

`compiler/pascal26 --where` prints:

```
Environment (tier 2 — overrides the exe-dir defaults, loses to -Fu/-I):
  PXX_HOME     (unset)   [exe-dir defaults in effect]
```

It does not override them. Measured 2026-08-29:

```
cp -r lib/rtl $S/home/lib/rtl
PXX_HOME=$S/home compiler/pascal26 --mimic-fpc -Fuexternal/synapse z.pas z
  ->  in: compiler/../lib/rtl/sockets.pas        { the ORIGINAL, not the copy }
```

And the decisive one — the probe that cannot be misread. With
`$PXX_HOME/lib/rtl/sockets.pas` **renamed away**, the compile behaved
identically, still reporting against `compiler/../lib/rtl/sockets.pas`. If
`PXX_HOME` were consulted at all, that had to fail as "unit not found". So the
variable is not merely losing a priority contest; it is not being read.

`-Fu` also did not redirect a *transitively* reached RTL unit here (a unit found
under the exe-dir default appears to resolve its own `uses` relative to its own
directory first), but that is a separate question and may be intended.

## Why it is worth fixing rather than documenting away

It removes the only clean way to test a compiler hypothesis against a **modified
copy** of the RTL. The alternative is editing `lib/rtl/**` in place — another
track's files — for an experiment that is meant to be reverted in a minute, which
is exactly the coordination hazard the lane rules exist to prevent. That is how
it was found: the experiment was abandoned rather than taken into Track B's
files.

## Fix shape

Either honour it where `--where` says it is honoured, or stop advertising it.
Silently ignoring a documented override is the worst of the three, because the
run *looks* like it used the override.

Found by frankA while working
[[bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream]].
