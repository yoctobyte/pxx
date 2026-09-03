---
prio: 80
track: A
type: bug
status: open
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
