---
prio: 55
track: A
type: bug
status: done
summary: "`r.matrix[0][0] := 'a0'` for a record FIELD of type `array of array of string[10]` is refused with `cannot assign ShortString to Char` -- the second index is resolved as a CHARACTER index into a frozen string instead of an element index into the inner array, so the whole shape is unreachable. The same declaration as a plain VARIABLE works on every target in both modes. FPC compiles and runs it. Blocks the only spelling that would exercise the field-rooted SetLength descriptor, which still has no frozen element capacity."
owner: frankA
---

# A field-rooted `array of array of string[N]` indexes as a Char

```pascal
type TS10 = string[10];
     TR = record matrix: array of array of TS10; end;
var r: TR;
begin
  SetLength(r.matrix, 3);
  SetLength(r.matrix[0], 3);
  r.matrix[0][0] := 'a0';        { pxx: error, FPC: fine }
end.
```

```
pascal26:8: error: incompatible types: cannot assign ShortString to Char
```

(`ShortString` under `-dPXX_SHORTSTRING`, `AnsiString` in the default mode --
same error, both modes, measured 2026-09-03 at `7bb56a21f826`.)

The same declaration as a VARIABLE — `var m: array of array of TS10` — compiles
and runs correctly on all seven targets in both modes. So the second `[...]` is
being resolved against the ELEMENT KIND rather than the remaining dyn depth, and
only when the root is a record field: `r.matrix[0]` is taken to be a
`string[10]` and `[0]` on it is a character index.

Two spellings of one construct disagree, which is
`devdocs/dev/normalise-dont-special-case.md`'s shape. The variable arm walks the
dyn depth from the symbol; the field arm asks the field's element kind.

## Why it is worth more than its own repro

**It is the only spelling that reaches the field-rooted SetLength descriptor.**
`SetLenDynElemSize` (`ir_codegen.inc`) answers the frozen element size from
`SymStrCap[symIdx]`, and a FIELD-rooted target has `symIdx < 0` and carries no
capacity on the node — so a frozen element there still gets the kind-only answer
(a pointer width) and the row would be allocated short, exactly the defect fixed
for the symbol-rooted case. That arm is left deliberately unfixed and documented
rather than patched blind, **because this bug makes the shape uncompilable and
there is therefore nothing to measure**. Fix this first; the descriptor arm then
has a repro and can be fixed against it rather than against a reading.

Carrying the size would mean a new side table beside `IRSetLenBaseRec`, so it is
not a one-liner and should not be done on speculation.

[[bug-a-storing-into-an-element-of-an-array-of-frozen-strings-bus-errors-on-xtensa]]

## Fixed 2026-09-03 — there were TWO dyn-depth walkers and the parser's had no field arm

`IsNodeArray` (symtab.inc) asked `DynArrayNodeDepth`, whose arms were AN_IDENT,
AN_DEREF, AN_INDEX, AN_DYN_COPY, AN_DYN_INSERT and AN_COMMA. Its twin
`NodeDynDepth` (ast_arena.inc) has all of those **plus AN_FIELD and the four
CALL kinds**. So `r.matrix` answered depth 0, `IsNodeArray(r.matrix[0])` was
FALSE, and the selector chain fell to the *index-a-string* arm — which typed the
second subscript a Char. The variable spelling took the AN_IDENT arm and was
right, which is why one construct had two answers.

The twin's own header said this would happen: *"These two functions ARE twins
and drift is the recurring failure here ... when you add a shape to one, add it
to the other in the same edit."* It had already been repaired that way twice
(the AN_DEREF widening, the AN_INDEX fixed-array-of-dyn case), each time by
copying an arm across.

**So the fix deletes the twin instead of adding a third arm to it.**
`DynArrayNodeDepth` is gone; `IsNodeArray` calls `NodeDynDepth` through a
forward declaration in `compiler.pas`, the pattern already used there for
`IsNilLiteralNode` (same direction: symtab.inc asking ast_arena.inc). One
walker, so the drift cannot recur. `NodeDynDepth` is a strict superset of what
was deleted — every arm the old one had, identical logic — so nothing that
answered before answers differently, and field- and call-rooted dyn arrays now
answer at all.

Verified `x86-64, i386, arm32, aarch64, riscv32` x `default, -dPXX_SHORTSTRING`:
all ten cells correct, self-host fixedpoint holds (1 round). Positive control:
a compiler built from this tree with the two files reverted REFUSES the new test
outright (`cannot assign ShortString to Char`), so the test cannot pass for
another reason.

Test: `test/test_field_rooted_nested_dyn_frozen_index.pas`, wired native + all
four runnable cross targets, both modes. It carries the frozen, AnsiString and
Integer element types, because the AnsiString spelling wore the same
`cannot assign ShortString to Char` face.

**One element per row on purpose, and this is the residual.** The ticket
predicted the field-rooted SetLength descriptor would need fixing next. It does,
and it now has a repro — but the missing piece is NOT the descriptor: the
capacity that would feed it is junk at the source (`RecFieldStrCap` answers 3
and 1 where both want 10). Measured, carrier built and reverted rather than
landed, and banked as
`bug-a-a-frozen-dynamic-array-field-records-a-junk-element-capacity` (prio 60) —
which is also wrong for the depth-1 spelling `row: array of string[10]`, a shape
that compiled all along and has been silently corrupting for longer.

Correction to this ticket's own text: the error is `cannot assign ShortString to
Char` in BOTH modes at `7bb56a21f826` and after, not `AnsiString` in the default
mode.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
