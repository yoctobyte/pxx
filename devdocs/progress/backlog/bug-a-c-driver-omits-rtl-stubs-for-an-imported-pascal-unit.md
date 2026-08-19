---
slug: bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit
track: A
prio: 55
status: backlog
---

# A Pascal unit whose body touches a managed string dies at import from C: "call to a runtime stub that was never emitted"

Found while building `feature-c-import-a-pascal-unit-under-a-mangled-name`. Not
a mangled-import bug — the import works; the unit never gets as far as being
imported, because compiling its BODY under the C driver fails.

## Repro

`u3.pas`:

```pascal
unit u3;
interface
function Tag: AnsiString;
implementation
function Tag: AnsiString;
begin Tag := ''; end;
end.
```

`t3.c`:

```c
#include "u3.pas"
int main(void){ u3_pas_Tag(); return 0; }
```

```
$ pascal26 -I. -Fu. t3.c o_t3
pascal26:6: error: compiler error: call to a runtime stub that was never emitted
  (code offset 0 is the ELF entry point). A frontend driver is missing its
  stub-emission call for the current flags/target.
  near:  begin Tag    >>> end  end
```

The error text says what it is: the C driver does not emit the managed-string
runtime stubs, so the assignment in the Pascal body compiles a call to offset 0.
Line 6 is the Pascal unit's line, not the C file's. Any string operation in the
body reproduces it — literal assignment and concatenation both.

The same unit compiled from a Pascal program is fine, so it is the DRIVER's
stub-emission call that is missing, not the lowering.

## Why it matters beyond the one feature

It is not confined to the mangled import. Any path that pulls a Pascal unit in
under the C driver hits it, and the failure is a `compiler error:` — the shape
that reads as "the compiler is broken", not "your program is wrong" — pointing
at a line in a file the C author did not write.

## Consequence for the importing feature

`feature-c-import-a-pascal-unit-under-a-mangled-name` refuses an AnsiString
RESULT by name (§5); that refusal cannot be exercised until this is fixed,
because nothing reaches it. The refusal code is landed and the test is written
against the day this closes.

## Gate

`make compiler/pascal26` + the repro above + `tools/gate.sh quick`.
