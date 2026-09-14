---
slug: feature-a-optional-imports-an-undefined-weak-dynamic-symbol
title: optional imports — an undefined weak dynamic symbol
summary: >
  `weakexternal` declares an import the program works WITHOUT. It emits an
  STB_WEAK undefined dynamic symbol; the loader zeroes the GOT slot when nothing
  defines it, `@f` reads nil, and the caller must test before calling. A library
  reached ONLY by weak imports emits no DT_NEEDED -- per LIBRARY, not per symbol
  -- because emitting one would LOAD the library to answer the question the weak
  import exists to ask; and a program whose imports are all weak collapses back
  to a STATIC link, or every threaded libc-free pxx program stops being static.
  The general answer to "use this C facility if the program already has it".
  Landed 5484ad6bb (x86-64 and i386); first consumer is the pthread route in
  lib/rtl/palthread.pas.
track: A
type: feature
prio: 60
owner: unassigned
status: resolved
resolved: 2026-09-14
blocked-by: []
---

## The surface

```pascal
function c_pthread_create(th, attr, start, arg: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_create';
...
if @c_pthread_create <> nil then ...
```

FPC's spelling, and it came off `IsInertRoutineDirectiveTok`'s refused list **by
being implemented**, which is the only way off that list.

## What it emits

`st_info` `$22`/`$20` (STB_WEAK) instead of `$12`/`$10`, in
`PrepareDynamicData`, `PrepareDynamicData32` and `writeELFSharedX64`. Three
`DT_NEEDED` loops skip a library whose every importer is weak.

`objdump -T` reads pxx's dynamic segment; `readelf --dyn-syms` prints nothing,
because pxx writes no section headers.

## Two traps, both measured 2026-09-14, both worth a minute

**The collapse must run before the ELF writers start.** First placed inside
`ResolveSynthImportLibraries` — called from the MIDDLE of `PrepareDynamicData`,
after the PT_INTERP string was appended and before `isDyn` was computed. The
result was a binary that was neither: no PT_INTERP, a stale interpreter string
in `.data`, and a jump to address 0 before the first `WriteLn`. The entry point
itself was valid, which made it read as a codegen fault. `DropWeakOnlyImports`
is now its own procedure, called as the first statement of all three exe writers.

**`PatchDynCallSites` must run unconditionally.** It was gated on
`ExternalCount > 0` alongside `PatchDynamicData`, which was harmless until the
collapse started zeroing that count. Ungated it walks `DynCallCount`, which is
independent. Gated, a collapsed binary kept placeholder displacements and `@f`
on an unresolved weak symbol answered **13258598199620634952** in a static link
against **0** in a dynamic one — so a correctly written `if @f <> nil` took the
WRONG branch and called into code bytes. The GOT slot was always zero; only the
displacement pointing at it was wrong.

## Tests

`test/test_weakexternal_absent.pas` (weak-only; asserts nil AND that the link
stays static), `..._present.pas` (a hard import beside a weak one that resolves
and a weak one that does not), `..._hard.pas` (the control: a plain `external`
of an undefined symbol must still fail at startup). The Makefile additionally
asserts the BINDING with `objdump -T` — `getppid` weak, `getpid` global — and
runs the i386 rows, which is where the st_info gap was found by reading the
sibling path rather than by a test.
