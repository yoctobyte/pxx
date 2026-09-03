---
prio: 55
track: A
type: bug
status: backlog
summary: "`r.matrix[0][0] := 'a0'` for a record FIELD of type `array of array of string[10]` is refused with `cannot assign ShortString to Char` -- the second index is resolved as a CHARACTER index into a frozen string instead of an element index into the inner array, so the whole shape is unreachable. The same declaration as a plain VARIABLE works on every target in both modes. FPC compiles and runs it. Blocks the only spelling that would exercise the field-rooted SetLength descriptor, which still has no frozen element capacity."
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
