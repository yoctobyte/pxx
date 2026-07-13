---
prio: 45
---

# `PInteger(p)^` does not compile, though `var p: PInteger` does

- **Type:** bug (compat — hard error, easy workaround)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** done

## Symptom
```pascal
var a: Integer; p: Pointer;
begin
  a := 7; p := @a;
  writeln(PInteger(p)^);     { error: undefined variable (PInteger) }
end.
```
`var p: PInteger` works. So does a user's own `type PInt = ^Integer; PInt(p)^`. Only the
built-in names fail **in a cast**. Same for PByte, PWord, PCardinal, PDouble, …

## Root cause
`ParseTypeKind` recognises these names in a TYPE position, but a type CAST resolves
through the **alias table** (`FindTypeAlias`), which has never heard of them. `PChar` /
`PAnsiChar` were given a cast path as a one-off (parser.inc ~7520); nothing else was.

## The obvious fix is a TRAP — do not take it
Registering them as real aliases at startup (`RegisterPtrAlias`, next to
RegisterBuiltinTGuid/TObject) looks right and even compiles. **It silently breaks the
compiler.** Tried 2026-07-13; the self-host byte-identical gate caught it.

`FindTypeAlias` scans FORWARD and returns the FIRST match. A builtin registered before
the source is parsed therefore **shadows the source's own declaration**. The compiler
itself declares `PWord = ^NativeInt` (the machine word — see the PWord/ILP32 landmine),
so a builtin `PWord = ^UInt16` would quietly re-type it and the self-compile stopped
being byte-identical. Units are lexed even later than the main source, so any RTL unit's
own `PInteger` would be shadowed the same way.

So any fix must make a source declaration WIN. Options, roughly in order of safety:
- give the CAST path the same builtin-name recognition ParseTypeKind already has,
  consulted only AFTER FindTypeAlias misses (smallest change; no shadowing possible);
- or make alias lookup last-wins (global semantics change — needs its own justification);
- or pre-scan and skip builtins the source redeclares (fragile: misses units, which are
  lexed after this point).

The first is almost certainly the right one: it puts the builtin names exactly where they
already live, and a real alias always takes precedence.

## Workaround
Declare the alias locally: `type PInt = ^Integer;`. Costs one line.

## Gate
`make test` + self-host byte-identical (this is the check that catches the shadowing —
do not skip it) + cross.

## Log
- 2026-07-13 — resolved, commit pending.
