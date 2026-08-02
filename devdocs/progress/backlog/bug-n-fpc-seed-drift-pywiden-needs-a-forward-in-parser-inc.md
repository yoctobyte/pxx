---
summary: "Third FPC seed drift in two days: parser.inc calls PyWiden, defined in pyparser.inc which is included 14 files later. Verified one-line fix. The rule is mechanical and worth stating once"
type: regression
track: N
prio: 60
---

# FPC seed drift #3: `PyWiden` called from `parser.inc`, defined in `pyparser.inc`

- **Type:** regression, cold-start bootstrap path — **Track N**
- **Filed:** 2026-08-02 by `claude@xeon` (Track T) from the `fpc-bootstrap`
  canary. Handed over, not fixed — T owns the tool, never the bug.
- The previous instance ([[bug-n-fpc-seed-drift-pybytesci-used-before-forward]])
  was fixed correctly; this is a **different identifier**, landed after it.

## The failure

```
parser.inc(14378,26) Error: Identifier not found "PyWiden"
compiler.pas(1031) Fatal: There were 1 errors compiling module, stopping
```

`PyWiden` is called at `parser.inc:14378` and defined at `pyparser.inc:860`.
`compiler.pas` includes `parser.inc` at line 86 and `pyparser.inc` at line 100,
so at the point of use FPC has not seen the definition.

## Verified fix — one line, in `parser.inc` (NOT pyparser.inc)

Beside the existing `PyMakeTruthy` forward at `parser.inc:857`:

```pascal
function PyWiden(a, b: TTypeKind): TTypeKind; forward;
```

Measured: `137001 lines compiled, 10.0 sec`, clean. Probe reverted; the tree
this was filed from is clean.

## The rule, stated once so instance #4 is avoidable

This is the third of these in two days and all three are the same mechanical
fact, so it is worth writing down rather than rediscovering:

> A `Py*` (or any cross-file) function **defined in `pyparser.inc` but called
> from `parser.inc`** must be forward-declared in **`parser.inc`**, because
> that file is included first — and it must NOT also be forward-declared in
> `pyparser.inc`, because FPC rejects a duplicate forward.

That second half is what made instance #1 subtle: `9d2d98856` had to *move* the
`PyMakeTruthy` forward, not add one, and left a comment saying exactly this.
The comment is on `PyMakeTruthy`; the rule is general.

pxx's own frontend resolves all of these without a forward, which is precisely
why the property is invisible to every check a dev actually runs — see
[[feature-t-fpc-seed-canary-closer-to-the-dev-loop]] for the Track T side. At
three occurrences in two days, that mitigation is looking less optional.

## Gate

`fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas` compiles clean and
the `fpc-bootstrap` canary goes green on the next watcher run.
