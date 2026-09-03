---
prio: 80
track: A
type: bug
status: done
summary: "REGRESSION SINCE PIN v401: on i386, `arr[0] = arr[1]` for `array[0..1] of string[8]` holding equal strings answers FALSE, in BOTH modes. Correct at the pin, correct at HEAD on every other target, and `arr[0] = a` against a plain variable is correct on i386 too -- it is element-vs-element specifically. Silent wrong answer, no diagnostic."
---

# i386: comparing two elements of an array of frozen strings is FALSE

```pascal
type TS = string[8];
var arr: array[0..1] of TS; a, c: TS;
begin
  arr[0] := 'abcde'; arr[1] := 'abcde'; a := 'abcde'; c := 'zz';
  WriteLn(arr[0] = arr[1]);   { i386 HEAD: FALSE     everyone else: TRUE }
  WriteLn(arr[0] = a);        { i386 HEAD: TRUE      correct }
  WriteLn(arr[0] = c);        { i386 HEAD: FALSE     correct }
end.
```

Measured 2026-09-03, both modes, `--target=i386` under qemu.

## It is a REGRESSION, which is the part that decides the priority

| | default | -dPXX_SHORTSTRING |
| --- | --- | --- |
| pinned compiler (v401) | TRUE | TRUE |
| HEAD | **FALSE** | **FALSE** |

Every other target is TRUE at HEAD in both modes, so this is i386-only and it
arrived with one of the frozen-comparison or frozen-argument changes that
landed on 2026-09-02/03. It has not been bisected.

## Why nothing caught it

`arr[0] = a` — element against a plain variable — is CORRECT, and that is the
row a suite naturally writes. Both operands being IR_INDEX is the failing
combination, and the failure value is FALSE, which is also the correct answer
for the unequal row sitting next to it. A must-be-TRUE row is the only shape
that sees this, and the file that now has one
(`test/test_frozen_compare_operand_shapes.pas`) is wired for native and wasm32
and deliberately NOT for i386 because of this ticket. Wire the i386 rows when
it lands — the Makefile says so at the point they were left out.

[[bug-a-a-frozen-string-compared-to-an-ansistring-is-false-under-the-flag-on-x86-64]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## Prio raised 70 -> 80 (coordinator, 2026-09-03)

**This is wrong in the DEFAULT mode — it ships today on i386.** Its sibling
(`...frozen-string-compared-to-an-ansistring...`) is flag-only and therefore
gated behind a flip that has not happened; this one is not gated behind
anything. Raised on the same reasoning used for the constructor/virtual ladder:
**a defect that needs no flag is live in every `$(PXX_STABLE)` build, and one
that needs the flag is not yet.**

It remains BELOW that ladder (92) because it is one target rather than four, and
below the flip blockers only in the sense that they are already closed. It is
the more URGENT of the two regressions for anyone building i386 now; its sibling
is the more DANGEROUS one for the flip. Those are different rankings and both
are true.

## Resolution (2026-09-03, frankB)

Bisected to **450f4b52a**, `fix(A): an array of shortstrings was STORED at one
prefix width and READ at another` — and that commit is not wrong. It had to
start tagging an IR_INDEX with the kind the ARRAY records, because that tag is
where the prefix width comes from. What broke is everything that had been
asking a DIFFERENT question of the same tag:

```pascal
if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
   ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString]) or
    (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString])) then
```

That guard means *is this a string at all*, and the comment under it said so
explicitly: *"The GUARD above still asks IntToTypeKind, which is correct: it is
asking 'is this a string at all', and the IR's generic tyString tag answers
that."* True when written; false the moment an element carried tyFixedString.
`arr[0] = arr[1]` then fell past it into the scalar path and compared two
ADDRESSES. `arr[0] = a` stayed correct because the variable's LEA is still
tagged generically and the OR fired on that side, which is why the natural
neighbouring row hid it.

### A SECOND VICTIM, ALL SEVEN TARGETS, AND IT DOES NOT COMPILE

The same enumeration in `ir.inc`'s case lowering:

```pascal
caseIsStr := IntToTypeKind(IRTk[selectorValNode]) in [tyString, tyAnsiString];
```

so `case arr[0] of 'abcde':` answered **`case label does not match the ordinal
selector type`** — a hard compile error on valid code, every target, both modes,
correct at the pin. `case r.f of` had it too under the flag (a record field
takes the same treatment, from fc926ef27, which is mine). Nobody had reported
either; there was no test with a non-trivial case selector.

### The fix, and why it is a predicate rather than three edits

`TypeIsAnyString(tk)` in symtab.inc — *is this a string at all*, beside
`TypeIsFrozenString`'s *does it carry an inline prefix* and `StrValTk`'s *what
does it present as*. A guard asking that question must not enumerate kinds,
because the set of kinds is exactly what this feature keeps changing. Applied at
the case selector and at both i386 compare guards (equality and ordering).

`ir_codegen_arm32.inc:1780` has the same enumeration in a STORE arm and is
deliberately left alone: `s := arr[0]` and `s := r.f` are correct there today on
every target in both modes, so widening it would be a change with no measured
defect behind it.

Verified in `test/test_frozen_compare_operand_shapes.pas`, which now carries the
case rows too: all seven targets, both modes, byte-identical to FPC 3.2.2.
Positive control: all three fixes reverted and the compiler rebuilt — the i386
row returns to FALSE, the case rows stop compiling, and the x86-64 flag row
returns to FALSE.

[[bug-a-a-frozen-string-compared-to-an-ansistring-is-false-under-the-flag-on-x86-64]]

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
