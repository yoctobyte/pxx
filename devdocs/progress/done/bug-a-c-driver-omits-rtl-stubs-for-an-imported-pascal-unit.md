---
slug: bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit
track: A
prio: 55
status: done
owner: frank1-ACP
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

---

## FIXED 2026-08-20 (frank1-ACP) — and the fix uncovered a second, worse defect

The ticket named one defect. There were **two**, stacked, and the second one is
the reason this could not be closed on the first: with the stubs emitted, the
repro compiled and then produced a **wrong string**, silently.

### Defect 1 — the missing stub-emission call (what the ticket describes)

`ParseCProgram` emits the div-by-zero stub, the `--threadsafe` I/O lock stubs
and the setjmp/fenv stubs, and never emitted the **AnsiString runtime**. A
Pascal unit's body lowers through exactly the same path as a Pascal program's,
so `Tag := ''` emitted `IREmitCodeCall(AnsiStrFromLiteralAddr)` with that
address still 0 — a call to the ELF entry point, caught by the guard in
`IREmitCodeCall` and reported as `compiler error:` at a line in a file the C
author never wrote.

The same failure class as
[[bug-a-threadsafe-segfaults-on-every-nilpy-program]] and the Div0 stub note
already in `cparser.inc`: a per-frontend stub-emission list that one frontend
forgot. That is now three times, which is why the forwards moved out of the
drivers rather than gaining a third copy — see below.

Emission is gated on the **same pre-scan the Pascal driver uses**
(`DetectPascalRuntimeNeeds`), not a C-specific guess, so a C translation unit
with no Pascal in it carries no shims. x86-64 only, like the Pascal path.

**Position matters and is not a style choice:** the shims sit right after the
entry stub and are reached by a *direct relative call*, so every caller — the
pulled RTL units included — must be compiled after them. That is why the
builtinheap forwards have to be registered first, and why emitting after the
RTL pull would be too late.

### Defect 2 — the unit was compiled as C

With the stubs in place the repro built and gave the wrong answer:

    function ConcatVarLit: Integer;
    var a, s: AnsiString;
    begin a := 'ab'; s := a + 'cdef'; ConcatVarLit := Length(s); end;

    from Pascal:  6      from C:  3

`CProgramMode` is a global "the program being compiled is C", and the lowering
reads it for things that are true of C **source** — most visibly a string
literal, which C mode adjusts by `+8` into a `char *`. The concat lowering then
sees an operand that is neither `tyAnsiString` nor `tyString` and takes the
**single-character** arm: `'cdef'` counted as one character. `PXXDBG=a.ir:A4`
shows it directly — `const_str tk=4` followed by `binop ... tk=17` (tyPointer).

`ParseCProgram`'s own RTL pulls never hit this, because they run **before**
`CProgramMode := True`. A user unit arrives through the `__pxx_pascal_unit`
token-stream marker, which is parsed during the C pass. So the rule already
existed and had one entry point that did not apply it; `CParsePascalUnitMarker`
now saves, clears and restores `CProgramMode` around `ParseUsesUnit`.

This is the worse of the two by the repo's own ranking: defect 1 is a loud
compiler error, defect 2 is a plausible wrong value far from its cause, in a
unit that gives the right answer when the same source is used from Pascal.

### Normalise, don't add a third copy

The builtinheap forward-registrations that must precede `EmitAnsiStringRuntime`
were written out by hand in `ParseProgram` and again in the NilPy driver, and
the C driver had neither. They are now one shared
`RegisterEmittedStringRuntimeForwards` in `parser.inc` — exactly the set the
emitter itself calls — used by the NilPy and C drivers. `ParseProgram` still
registers a much larger, target-conditional superset inline (variants,
interface ARC, the float writers, the xtensa divide helpers) and is left alone;
the helper's comment says so, so the next driver that needs the emitted runtime
has one call to make instead of a block to copy.

### Tests

- `test/cpasunit_strings.pas` + `test/c_pasunit_strings.c` +
  `test/test_c_pasunit_strings.pas`. The **oracle is the Pascal driver
  compiling the same unit**, and the Makefile diffs the two programs' output —
  so there is no expected string that could be quietly edited to match a
  regression. Covers literal assignment, managed+literal, literal+managed,
  managed+managed, a three-literal chain, indexing, and copying out through a
  `PChar` buffer.
- `test/cpasunit/strmod.pas` gained `function Tag: AnsiString`, and
  `test/c_pasunit_ansistring_result_fail.c` pins the **result-side** §5
  refusal. That is the refusal this ticket said "cannot be exercised until this
  is fixed, because nothing reaches it" — it is exercised now. The unit's body
  building a managed string is also what makes it a live regression test for
  defect 1.

All ten pre-existing `c_pasunit*` assertions re-run green, and `gate.sh quick`
is GREEN.

### Consequence for the importing feature

[[feature-c-import-a-pascal-unit-under-a-mangled-name]] §5's refusals are both
reachable now. Nothing there needs changing.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
