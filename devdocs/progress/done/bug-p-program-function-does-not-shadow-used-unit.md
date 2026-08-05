---
summary: "SILENT: a function declared in the PROGRAM does not shadow a same-named routine from a used unit — the unit's version is called instead. FPC calls the program's. Verified on sysutils IntToStr, Trim and UpperCase"
type: bug
track: P
prio: 70
---

# A program's own function does not shadow a used unit's — the unit wins

- **Type:** bug — **SILENT** wrong resolution. Track P (Pascal frontend name
  resolution).
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track B, while checking that a proposed duplicate-definition
  check would not break legitimate shadowing
  ([[bug-a-duplicate-definition-silently-accepted]]). Testing what shadowing is
  *supposed* to do turned this up.

## Symptom

```pascal
program s;
uses sysutils;
function IntToStr(v: Int64): AnsiString; begin IntToStr := 'mine'; end;
begin writeln(IntToStr(5)); end.
```

    FPC : mine        <- the program's own function
    pxx : 5           <- sysutils.IntToStr

**The user writes a function and the compiler calls somebody else's.** No error,
no warning, and the program is perfectly reasonable Pascal.

Verified on three unrelated routines, so it is not one function's quirk:

| program declares | FPC | pxx |
| --- | --- | --- |
| `IntToStr(v: Int64): AnsiString` | `mine` | `5` |
| `Trim(const t: AnsiString): AnsiString` | `trimmed-by-me` | `x` |
| `UpperCase(const t: AnsiString): AnsiString` | `MINE` | `AB` |

Signatures match the RTL's exactly, so this is not overload competition picking
a better-fitting candidate — the inner declaration is simply not preferred.

## What DOES work, and why that matters

Shadowing a **builtin** works and agrees with FPC:

```pascal
function UpCase(c: Char): Char; begin UpCase := 'X'; end;   { prints X, as FPC }
function Length(const t: string): Integer; ...              { prints 99, as FPC }
```

So the scope machinery prefers a program declaration over a *builtin* but not
over a *used unit*. That asymmetry is the shape of the defect and probably the
place to look.

## The same defect shows between two UNITS

Two units exporting the same routine is legal Pascal — FPC accepts it silently
and the **last** `uses` wins:

```pascal
uses ua, ub;   begin writeln(Who); end.    { FPC: B   pxx: A }
uses ub, ua;   begin writeln(Who); end.    { FPC: A }
```

pxx picks the **first** unit where FPC picks the last. Same underlying rule
missing — a later declaration must shadow an earlier one — so this is likely one
fix, not two, and the unit-vs-unit case is the cheaper reproduction.

## Relationship to the Random bug

[[bug-pascal-unqualified-call-binds-builtin-over-used-unit]] (done) is the
adjacent pair — **builtin vs used unit**, where the builtin wrongly won. This is
**program vs used unit**, where the unit wrongly wins. Same area, different
pair, and this one is not covered by that fix: it was measured on the current
pinned stable.

## Why urgent

Silent, and it defeats an ordinary and deliberate act. Shadowing an RTL routine
is how you patch behaviour locally without forking the unit — and here the local
patch is compiled, called by nothing, and quietly ignored while the original
runs. Anyone doing it would conclude their code never executes, with no
diagnostic pointing at name resolution.

## Gate

The program's own declaration wins over a used unit's for an unqualified call,
matching FPC; `sysutils.IntToStr(5)` still reaches the unit's version when
qualified. Worth an entry in the Pascal frontend tests covering all three scopes
at once — builtin, unit, program — since the builtin case already behaves and a
fix must not regress it.


## Fixed 2026-08-05 — the silent half; the other two are split out

### Fixed: a program's own routine beats a used unit's

    function IntToStr(v: Int64)        + IntToStr(Int64(5))  ->  mine
    function Trim(const t: AnsiString) + Trim(a)             ->  mine-trim
    sysutils.IntToStr(Int64(7))                              ->  7   (qualified still reaches the unit)
    function UpCase(c: Char)                                 ->  X   (builtin shadowing unregressed)

Two matches with the same signature are indistinguishable, so the only thing
left to rank them by is scope — and the lookup chain is FIFO = **registration
order**, which puts used units ahead of the compiling scope's own routines.
Both resolvers now prefer a match in the **current scope**: `FindProc` (used
for paramless calls, and as the representative of a same-named set) and
`MatchProcCall`'s **exact-match phase**.

Only that phase. The later compatible/lifting phases rank by argument *fit*,
where a better-fitting routine should win wherever it lives.

### Split out: `uses a, b` order (was this ticket's unit-vs-unit half)

[[bug-p-uses-order-does-not-decide-which-unit-wins]], prio 35. The ticket's
guess that this was "likely one fix, not two" was wrong — the two halves live
in different resolvers, and the unit-vs-unit one is genuinely hard. See below.

### Split out: arguments that need a conversion

    IntToStr(5)   ->  '5'    (FPC: mine)
    Trim(' x ')   ->  'x'    (FPC: mine)

Not the same defect. sysutils declares exactly one `IntToStr` (`Int64`), so
nothing wins on fit: `5` types as `tyInteger`, the exact-match phase misses
*both*, and the compatible phases rightly see two equally convertible routines.
The real difference is structural — **FPC hides, pxx competes**: an FPC inner
declaration removes the outer same-named set from consideration entirely absent
an explicit `overload`. That is a repo-wide resolution semantics change, parked
as [[decide-inner-declaration-hides-or-competes-with-outer-overloads]] rather
than guessed at.

The ticket's practical motivation — patching an RTL routine locally — now works
whenever the call site's argument types match the declaration, the ordinary case.

## The two near-misses, recorded because the quick tier passed both

The first version preferred the **last chain entry** outright, which is FPC's
uses-order rule. It broke two unrelated things, and `gate.sh quick` was green
for both:

1. **The compiler could not compile itself** — `set item must be one character`
   at `EmitAsmX64([...])`. That routine has `array of const` and `AnsiString`
   overloads, and the parser reads the returned proc's **signature** to decide
   whether `[...]` is an open-array constructor or a set.
2. **The NilPy stdlib segfaulted** at `sum(range(i))`, caught only by
   `--tier limited`. `pyparser.inc` infers expression types from
   `Procs[procIdx].RetType` off whatever `FindProc` returns.

Root of both: **`FindProc` returns a representative of a same-named set and
callers read types and signatures off it** — it is not a pure "what does this
call bind to" query. Any ranking change there needs the limited tier at
minimum. That is the whole reason this landed as current-scope-only.

Test: `test/test_shadow_program_over_unit.pas` — all four cases at once (unit,
builtin, qualified, own).

**Resolved:** PENDING-COMMIT

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
