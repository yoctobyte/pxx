---
summary: "Pascal: uses is transitive — a unit's own uses leak into everything that uses IT, for routines and classes alike (one flat global namespace)"
type: bug
track: A
prio: 65
---

# Pascal: `uses` is transitive, so every unit's imports leak to its consumers

- **Type:** bug (name resolution / unit visibility) — **Track A**
- **Status:** working
- **Opened:** 2026-07-28, from [[decide-class-namespace-scoping]]. This is the
  root cause that ticket is a symptom of.

## Repro — routines (pure Pascal, no NilPy involved)

```pascal
unit priv;
interface
function Wrap(const s: AnsiString): AnsiString;
implementation
uses sysutils;                        { implementation section — private by any reading }
function Wrap(const s: AnsiString): AnsiString;
begin
  Result := Format('[%s]', [s]);
end;
end.
```
```pascal
program tp;
uses priv;                            { sysutils appears NOWHERE in this program }
begin
  writeln(Wrap('a'));                 { [a]  — fine }
  writeln(IntToStr(9));               { 9    — WRONG: should be "undefined variable" }
end.
```

Observed with `stable_linux_amd64/default/pinned`. `IntToStr` resolves although
the program never used sysutils, and although `priv` imported it in its
implementation section.

## Expected

Pascal's `uses` is not transitive, in EITHER section. If A uses B, a unit that
uses A does not see B's names — it must list B itself. The section
(interface vs implementation) controls circular-reference legality and whether
B's types may appear in A's *interface* signatures; it is not what makes the
import private. Non-transitivity is what does that, and pxx does not implement it.

## Cause

One flat global namespace, for both axes:

- **Routines** — procedure lookup walks all units. `IRFindProc1ByArgTk`
  (`compiler/ir.inc`) says so outright: *"across ALL units. FindProcOverload is
  scoped to CurrentUnitIdx, so it cannot see pylib's pystr_of from the main
  program being lowered."*
- **Classes** — `FindUClass` (`compiler/symtab.inc:386`) is first-match over
  `UClsCount`, with a unit-preference pass in front of it and a hard-coded
  exception list (`ClassNameIsDeliberatelyShared`, `:331`) to keep the
  preference from breaking `Exception`.

The uses clause records dependency and parse order; it does not gate visibility.

## What it costs today

Every consequence below is the same missing rule wearing a different hat:

1. **`decide-class-namespace-scoping` in full.** tkinter's `Canvas` and
   reportlab's collide because both are in one namespace. With non-transitive
   `uses` they are simply different names in different scopes — no new syntax, no
   `replaces` declaration, no shared-name list.
2. **`ClassNameIsDeliberatelyShared` exists only because of this.** With real
   scoping, `pylib uses sysutils` (or the reverse) gives ONE `Exception` by
   construction and the list is deleted, along with the duplicated `CreateFmt`
   bodies described in that ticket.
3. **NilPy programs inherit Pascal's namespace.** A `.npy` that reaches sysutils
   gets its exports unqualified, and Pascal is case-insensitive while Python is
   not, so `format`, `date`, `time`, `trim`, `pos`, `copy`, `delete`, `insert`
   and friends all shadow. Measured: `print(format(255))` in a `.npy` that
   imports sysutils reports `format(AnsiString, record)` — a Pascal signature
   error against Python source — where without sysutils it correctly says
   `undefined variable (format)`. User `def`s DO win, so only undefined names are
   affected, but the failure mode is a silent bind to Pascal semantics instead of
   a NameError.
4. Related in kind, filed separately: [[bug-nilpy-stdlib-name-binds-pascal-unit]]
   (a Python stdlib import binding to a same-named RTL unit).

## Sizing before committing

The tree currently gets names for free everywhere, and some of that WILL break —
the size of the breakage decides whether this is one ticket or a campaign. Cheap
measurement first: resolve exactly as today, but WARN whenever a name resolves
through a unit that is not in the current unit's own uses (transitively via
interface-section uses, per the real rule). Build the tree, count and classify the
warnings. That is an afternoon and it turns the estimate into a number.

Expect the RTL itself to be the biggest consumer of the current laxity.

## Fix shape

Visibility set per unit = its own uses + the interface-section uses of those
units, transitively closed over INTERFACE sections only; implementation-section
uses stay private to the importing unit. Applied uniformly to the routine table
and to `FindUClass`/`FindUField`. Then the class-preference pass and its shared
list both come out.

## Gate

`make test` + `make test-nilpy` + self-host byte-identical + cross, with `test/`
cases for the routine repro above and for two units legitimately exporting the
same class name. Land incrementally or behind a flag — this changes resolution
for the whole tree and is exactly the kind of change that should not arrive as
one commit.

## Measurement step, as designed (2026-07-28)

Taking the ticket's own advice — resolve exactly as today, warn when a name
resolves through a unit the current unit cannot legitimately see, then count.
Shape of that work, so it can be picked up in one sitting:

1. **Edge table.** No per-unit uses graph exists today; `ParseUsesUnitBody`
   records dependency and parse ORDER only. Add three parallel arrays —
   `UsesFrom` (Strs idx of the importing unit, -1 = main program), `UsesTo`,
   `UsesInIface` (Boolean) — appended wherever a uses clause names a unit. The
   section is known from where the clause is parsed; the parser has no
   interface/implementation flag today, so one has to be threaded through (the
   `implementation` keyword is matched by string compare at several sites, so
   the state is genuinely absent, not merely unnamed).

2. **`VisibilityAllows(curUnit, declUnit)`.** True when `declUnit = curUnit`,
   or `declUnit` is reachable from `curUnit` by one edge of EITHER section
   followed by INTERFACE-section edges only, transitively. That is the real
   Pascal rule: the section controls whether the import is re-exported, not
   whether it is legal.

3. **Warn, behind `--warn-uses-leak`.** Opt-in so an ordinary build is
   unchanged and the measurement can run over the whole tree without touching
   any gate. Call it from the routine lookup the Pascal identifier path uses
   and from `FindUClass`.

4. **Count and classify** over `make test` + `make lib-test` + the corpora.
   The expected shape of the answer: the RTL is the biggest consumer of the
   current laxity, and the interesting number is how many DISTINCT (importing
   unit, resolved unit) pairs appear rather than how many call sites.

Only after that number exists is it worth deciding between "one ticket" and
"a campaign" — and the enforcement itself should land behind the same flag
before it becomes the default.
