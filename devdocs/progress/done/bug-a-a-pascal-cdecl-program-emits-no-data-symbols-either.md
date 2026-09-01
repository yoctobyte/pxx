---
type: bug
track: A
prio: 60
type_note: the Pascal half of the object data-symbol work
tags: [emit-obj, elf, symbols, pascal, linkage]
summary: "RESOLVED d402147d6 by adding the spelling that was missing rather than an export pass: `cvar` / `public` on a Pascal global did not parse at all, so no source could say a global is part of its object's interface and the count could only be 0. A marked global is now OBJECT GLOBAL with its real size; an UNMARKED one stays absent -- deliberately NOT the blanket export this ticket's acceptance asked for, because Pascal gives a var block no linkage rule to read and exporting every global collides with the host. `external` on a var is refused, not swallowed."
status: done
owner: frankA
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


## RESOLVED — d402147d6, and the acceptance above was changed, not just met

Landed as `cvar` / `public` on a Pascal global. Read the divergence from this
ticket's own acceptance before reusing it:

**This ticket asked for "a `cdecl` program's own `var` block globals appear as
OBJECT GLOBAL". That is not what shipped, and it should not have been.** The
defect was never a missing export pass — it was a missing SPELLING. `var x:
Integer; cvar;` answered *"expected ':' before ';'"*: the directive follows the
semicolon that ENDS the declaration, so it arrived looking like the start of the
next one. `public` and `external` were the same. With no way to say it, the
count could only be 0.

Exporting every global instead would contradict the writer's own stated rule,
one screen above the code this touched: only `cdecl` routines export, *"so an
object cannot collide with its host over an RTL name"*. `var i: Integer` in two
pxx objects, or against a host's `i`, is a duplicate definition the link
refuses — and this ticket's own third acceptance row asks for exactly that
collision, which is an argument against exporting things nobody nominated.

**The asymmetry with the C half is the two LANGUAGES, not an inconsistency.**
C 6.9.2 gives a file-scope variable external linkage as a language rule, so
exporting it is reading C. Pascal gives a var block no linkage concept, so
there is nothing to read and the compiler must be told.

My first cut *was* the blanket version, gated on "declared in the file the user
named". Wrong in both directions: a unit of a multi-unit program that writes
`cvar` means it, and a program's unmarked globals are not an interface just
because the user typed that filename. The provenance field it needed
(`MainSrcPath`) was removed with it rather than left unread.

### Measured

Fixture declares four globals, marks two, and `uses sysutils` (which brings ~24
more, plus ~23 from the builtin runtime).

- exported: `GCount` (cvar, 4 bytes) and `GPub` (public, 4 bytes) — exactly two,
  asserted as an exact count on x86-64 and i386.
- **not** exported: `GHidden` and `GName`, absent from the symbol table
  entirely, while still being read through exported routines. That is the half
  that matters; "the two I wanted are present" passes equally on an object that
  exported all fifty.
- a C `main` reads 7 from the Pascal initialiser, writes 100 and Pascal reads it
  back, Pascal bumps and C sees 101 — x86-64, and i386 under `gcc -m32`.
- a C host redefining `int GCount = 1;` FAILS to link (`multiple definition`),
  read as a differential against the row above it: same object, same shape of
  main, one added line. So the export is a real definition, not weak and not
  `SHN_COMMON`.
- the "defines no linkable symbol" refusal keeps its positive control: that
  program's `g` carries no directive, so its object is still refused.
- `errno`/`environ` touched by the host on both targets; no RTL global exported.

### Left open, deliberately, each with a ticket

- `external` on a variable — the IMPORT direction — is REFUSED with a message
  naming [[bug-a-a-pascal-global-cannot-import-a-c-global]]. Accepting the
  keyword without the relocation routing would allocate local storage and read
  zero forever: the parent ticket's silent-wrong-read, pointing the other way.
- `name '...'` on either directive is refused for the same reason: it would
  otherwise export under the wrong name, silently.
- **xtensa and riscv32 are NOT covered**, and this is not an omission in the
  data work. Measured: a riscv32 object from this fixture exports exactly ONE
  symbol, `app_main`, and every proc is LOCAL FUNC — that writer has never
  exported a `cdecl` routine either.
  [[bug-a-the-esp-object-writer-exports-only-app-main-so-no-cdecl-routine-or-global-is-linkable]]
- Found beside this work and not caused by it: an i386 object has 0 absolute
  `.text` relocations for a bare program and 62 once it says `uses sysutils`, so
  it cannot link into a hardened PIE. The `cvar` directives were the control —
  62 with and without.
  [[bug-a-an-i386-object-carries-text-relocations-as-soon-as-it-uses-sysutils]]

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9a6b936ec.


## Correction to the repro quoted above — it reads freed memory

The `pg2` program in "Measured, by Track B" returns `PChar(GName + '/' +
GTable[i])`, and the write-up reads its correct-looking output as evidence that
"the globals are initialised, mutated and survive across calls". The output is
correct; the reasoning is not, and the symbol-table finding the ticket was
filed on does not depend on it.

Re-measured 2026-09-01 at `a4c67a5e6cc8`, same source, same C main, one flag
added:

```
$ ./compiler/pascal26 -Fulib/rtl --emit-obj pg2.pas pg2.o && gcc main.c pg2.o -o pg2 && ./pg2
global-string!/a
global-string!!/bb
global-string!!!/ccc

$ ./compiler/pascal26 -Fulib/rtl -dPXX_HEAP_DEBUG --emit-obj pg2.pas pg2d.o && ...
<24 bytes of 0xDD>   (x3)
```

The concatenation is a TEMPORARY and the `PChar` points into it, so it dies at
`return` under any ownership model — the first run prints correctly only
because nothing has reused the block yet. Track B's string-ownership work
(`b788c5865`, `IRParkManagedStr`) makes the lifetime of a managed string
reaching a pointer destination scope exit rather than forever, which is
plausibly why this now frees where it previously leaked; **not bisected here,
and it is Track B's topic** — the mechanism above holds either way.

Keep the shape out of interop examples: a `cdecl` routine returning `PChar` has
to return a pointer the CALLER owns or one that outlives the call.
