---
type: bug
track: A
prio: 60
type_note: the Pascal half of the object data-symbol work
tags: [emit-obj, elf, symbols, pascal, linkage]
summary: "--emit-obj on a PASCAL cdecl program still emits no data symbol: `nm --defined-only | grep -cE ' [BbDd] '` is 0 for a program with AnsiString and array globals. The C half landed in 72000d1e1; membership is set only by the C parser, so Pascal globals were never candidates. Needs its own 'whose declaration is this' answer -- exporting every RTL global is the failure mode one line away, and the C half hit exactly that with errno/environ."
---

# A Pascal cdecl program emits no data symbols either

Split out of
[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]]
when its C half landed (`72000d1e1`). That ticket's acceptance said "both
frontends, since Pascal `cdecl` units have the same exposure". Only the C
frontend is done. Filed rather than left implied, because the C half's symbol
tables now look complete and a reader could reasonably assume the Pascal ones do
too.

## Measured, by Track B, independently of the C work

A Pascal program with `cdecl` exports and string/array globals builds and runs
correctly through `--emit-obj`:

```pascal
program pg2;
var GName: AnsiString = 'global-string';
    GTable: array[0..2] of AnsiString = ('a', 'bb', 'ccc');
function pick(i: Integer): PChar; cdecl;
begin
  GName := GName + '!';
  pick := PChar(GName + '/' + GTable[i]);
end;
begin
end.
```

A C `main` calling `pick(0..2)` prints `global-string!/a`,
`global-string!!/bb`, `global-string!!!/ccc` — so the globals are initialised,
mutated and survive across calls into the object.

**And `nm --defined-only pg2.o | grep -cE " [BbDd] "` is 0.** Every symbol is
`t`. The globals are real and live in `.bss`; nothing names them to the linker.
That is the same defect the C half fixed, in the other frontend.

Two shape constraints found while constructing it, worth keeping: an `exports`
clause is rejected by the parser ("expected 'begin' before 'exports'"), and
`--emit-obj` on a `unit` errors ("this file is a unit, not a program"). So the
carrier has to be a *program* defining `cdecl` routines.

## Why it is not a one-line extension of the C half

The writer is ready: `ObjPlanHostedSymbols` walks three data groups and both
writers emit them. What is missing is MEMBERSHIP. `SymCFileScope` is set in
`ParseCGlobalVarDecl` and nowhere else, so a Pascal global is never a candidate
and the whole mechanism is inert for it.

**The obvious extension — "mark every `skGlobal` with a name" — is the failure
mode, and the C half already walked into it.** crtl is compiled as C and bundled
into every object, so its file-scope variables ARE C file-scope variables; the
first version of the C half exported `errno`, `environ`, `optarg`, `optind`,
`opterr`, `optopt` and `optreset`, and the link failed outright because glibc's
`errno` is TLS in `.tbss` and ours is not. The Pascal side has the same shape and
a far larger surface: every RTL unit's globals would join.

So this needs a Pascal answer to "whose declaration is this". `PasMarkTokFile`
exists and is the likely instrument — the C half uses `CModuleOfTok` plus the
interned module PATH, and deliberately not the module ID (see `CDeclIsFromCrtl`
for why: under `--emit-obj` the user's own file has a real module range, so
"id < 0 means the main source" is false there).

## Acceptance

- A `cdecl` program's own `var` block globals appear as `OBJECT GLOBAL` with
  real sizes; `nm --defined-only | grep -cE ' [BbDd] '` is greater than 0.
- **No RTL global is exported.** This is the control that matters, and it must
  be asserted positively: link the object into a gcc `main` that also uses
  libc's `errno`/`environ` and check it still links.
- A Pascal object and a C object defining the same name collide at link time,
  as two C objects already do.
- x86-64 and i386, both writers, since the index arithmetic is per writer.
