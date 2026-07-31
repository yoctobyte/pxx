---
summary: "Pascal: {$define} in one unit stays visible in units parsed afterwards, so {$ifdef} compiles different code depending on uses ORDER"
type: bug
track: A
prio: 55
---

# Pascal: conditional defines leak across unit boundaries

- **Type:** bug (lexer / conditional compilation) — **Track A**
- **Status:** working
- **Opened:** 2026-07-28, while investigating [[decide-class-namespace-scoping]]
  (an `{$ifndef}` guard was floated as a way to let two units cooperate on one
  class declaration — it appeared to work only BECAUSE of this bug).

## Repro

Two units, one defining a symbol, one testing it. Neither includes the other.

```pascal
unit ua;
{$define LEAKED_FROM_UA}
interface
procedure A;
implementation
procedure A; begin writeln('ua'); end;
end.
```
```pascal
unit ub;
interface
procedure B;
implementation
procedure B;
begin
{$ifdef LEAKED_FROM_UA}
  writeln('ub SEES ua''s define');
{$else}
  writeln('ub does not see it');
{$endif}
end;
end.
```

Compile two programs that differ ONLY in the order of the uses clause:

```pascal
program t2; uses ua, ub; begin A; B; end.   { -> "ub SEES ua's define" }
program t3; uses ub, ua; begin B; A; end.   { -> "ub does not see it"  }
```

Both observed with `stable_linux_amd64/default/pinned`. Same two units, different
machine code, no diagnostic.

## Expected

FPC/Delphi scope conditional symbols to the unit being compiled: each unit starts
from the command-line/`-d` defines and whatever it pulls in textually via `{$i}`,
and a `{$define}` in another unit is invisible. `ub` must print "ub does not see
it" in both programs.

**C is not a counterexample.** C has no cross-translation-unit defines either: a
TU is one .c file plus what it textually includes, and a different TU starts
clean. Include guards protect against the same header being pulled in twice
*within one TU* through nested includes — not against leakage between TUs. So C
is per-TU and Pascal is per-unit; both reset at the compilation-unit boundary.
pxx is the odd one out: it parses the whole program in one pass and the define
table simply accumulates.

## Cause

`PasInitDefines` (`compiler/lexer.inc:739`) is called exactly once, from
`compiler/compiler.pas:175`. Nothing resets or scopes `PasDefineCount` /
`PasDefineNameOff` / `PasDefineActive` between units, so every `{$define}` is
global from its point of declaration onward — which is why the behaviour is
ORDER-dependent rather than merely global: a unit parsed before the definer does
not see it, one parsed after does.

## Fix shape

The save/restore already exists in tree and can be reused verbatim in shape:
`ExpandIncludes` (`compiler/elfwriter.inc:3065` … `:3307`) snapshots
`PasDefineCount`, `PasDefineCharLen`, `PasDefineActive`, `PasDefineHasValue` and
`PasDefineValue` around its pre-pass and restores them after. The same
save/restore around each unit parse gives per-unit scoping.

Watch for: defines set by command line / target seeding must survive the reset
(they are the baseline every unit starts from, see the `PasInitDefines` seeding
note at `lexer.inc:847`), and `{$i}` includes must still inherit the *including*
unit's state, since textual inclusion is exactly the case where top-down
visibility is correct.

## Why it matters beyond conformance

The failure is silent and produces different object code from identical sources.
It also makes any "guard a declaration with `{$ifndef}`" arrangement between two
units *appear* to work while quietly depending on parse order — the trap that
surfaced this.

## Gate

`make test` + self-host byte-identical, with a `test/` case built from the repro
above asserting BOTH uses orders print "ub does not see it".
