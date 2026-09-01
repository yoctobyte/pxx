---
type: bug
track: A
prio: 45
tags: [emit-obj, elf, symbols, pascal, linkage]
summary: "`var x: Integer; cvar; external;` is REFUSED, so a Pascal object can export a global to C but cannot read one C defines. The C frontend has the import path already (ObjDataIsImport routes the reference to an UND symbol); Pascal has no spelling that reaches it, and accepting the keyword without the routing would allocate local storage and silently read zero."
status: done
owner: frankA
---

# A Pascal global cannot import a C global

The export direction landed in `d402147d6`: a Pascal global marked `cvar` or
`public` becomes an `OBJECT GLOBAL` a C host can read and write by name. The
other direction does not exist. `external` on a variable is refused with a
message naming this ticket, deliberately, rather than swallowed.

## Why it is refused rather than accepted

The keyword alone is not the feature. A variable declared `external` still
takes global storage through `AllocFromDeclTypeDesc`, and every reference to it
relocates into **this object's own `.bss`**. Accepting the keyword and doing
nothing else gives a program that compiles, links, and reads zero forever —
the exact silent-wrong-value shape the parent ticket was filed about, only
pointing the other way.

## What the work is

Most of it already exists, for C. `SymCExternOnly` records "every declaration
said extern and none defined it"; `ObjDataIsImport` reads it; both writers
route the reference to `impSym0 + ObjDataImportOrdinal(...)` instead of to a
section. What is missing on the Pascal side:

- parse `external` (and `cvar; external;`) in the var-directive branch of
  `ParseVarSection`, where `cvar`/`public` are handled now;
- set the import flag — and RENAME it first. `SymCExternOnly` is C-named and
  would then be set by two frontends, which is the 80%-accurate label
  `SymObjDataScope` was renamed out of one commit earlier.
- decide what a NON-object build does with it. C has the same gap today and
  answers silently; that is not a reason to add a second silent answer.

## Acceptance

- A C `main` defines `int Shared = 5;`, a Pascal object declares it `cvar;
  external;`, and an exported Pascal routine reads 5 — then writes 6 and the C
  side sees 6.
- The Pascal object's symbol table shows `Shared` as `NOTYPE GLOBAL UND`, and
  its `.bss` did NOT grow by the variable's size.
- An `external` variable that nothing references emits no UND symbol, matching
  the rule the C half already follows.
- x86-64 and i386, both writers — the index arithmetic is per writer, and that
  is how the C half's i386 object came out truncated the first time.
- Refused, not silent, in a non-object build, until that question is answered.

## Resolved

frankA, 2026-09-01. Compiler `69eeb1efd71e`. Regression rows: `test-emit-obj`
block 4b-quater-bis over `test/c_obj_import_pascal.pas` +
`test/c_obj_import_host.c`, x86-64 and i386.

Both spellings work — `cvar; external;` (two chained directives) and the bare
`external;` a Pascal programmer would write — and the directive applies to the
whole declaration group, so `ImpA, ImpB: Integer; external;` imports both. All
three come out `NOTYPE GLOBAL UND`; the C host's 5/10/20 read back as 35, and
the object's write to `ImpCount` is visible to C as 6.

**The flag was renamed first, as the ticket asked.** `SymCExternOnly` is now
`SymObjDataExternOnly`: two frontends set it, and a C-named flag set by the
Pascal parser is the 80%-accurate label this family keeps producing. The C
6.9.2 fold rule it documents is unchanged and still correct for Pascal by
being trivial there — a Pascal declaration either says `external` or does not,
so there is no tentative definition to outrank it.

**Refused, not silent, where there is no import to bind to.** Outside
`--emit-obj` an executable has no link step that could resolve the name, so
the keyword errors rather than falling back to the pre-implementation
behaviour of local storage reading zero. An initializer on an `external`
variable is refused for the same reason. Both refusals have their own rows,
and the non-object row asserts the error TEXT — without that it passes on any
compile failure at all.

**One acceptance bullet turned out to describe something the C half does not
do.** "Its `.bss` did NOT grow by the variable's size" — measured, a C
translation unit containing `extern int Big[1000];` has exactly the same
`bss=` as one containing `int Big[1000];`, 42156B both. The storage is
reserved before the extern-fold is final and never reclaimed. Pascal now
matches C rather than diverging from it, and the reservation is filed as
[[feature-a-an-extern-only-variable-still-reserves-its-storage]] at prio 25 —
wasted space, never a wrong value, and the same currency as the crtl
duplication ticket.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7b7ab0ed2.
