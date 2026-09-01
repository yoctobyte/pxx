---
type: bug
track: A
prio: 45
tags: [emit-obj, elf, symbols, pascal, linkage]
summary: "`var x: Integer; cvar; external;` is REFUSED, so a Pascal object can export a global to C but cannot read one C defines. The C frontend has the import path already (ObjDataIsImport routes the reference to an UND symbol); Pascal has no spelling that reaches it, and accepting the keyword without the routing would allocate local storage and silently read zero."
status: working
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
