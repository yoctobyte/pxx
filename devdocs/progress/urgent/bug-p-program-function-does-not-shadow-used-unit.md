---
summary: "SILENT: a function declared in the PROGRAM does not shadow a same-named routine from a used unit — the unit's version is called instead. FPC calls the program's. Verified on sysutils IntToStr, Trim and UpperCase"
type: bug
track: P
prio: 70
---

# A program's own function does not shadow a used unit's — the unit wins

- **Type:** bug — **SILENT** wrong resolution. Track P (Pascal frontend name
  resolution).
- **Status:** urgent
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
