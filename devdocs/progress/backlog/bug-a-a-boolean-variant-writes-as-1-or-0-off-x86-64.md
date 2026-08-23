---
track: A
prio: 40
type: bug
blocked-by: []
status: backlog
summary: "`writeln(v)` with v a Boolean Variant prints True/False on x86-64 and 1/0 on i386, arm32 and aarch64. Same source, same program, different output per target -- and the 1/0 form is not what FPC prints either. Pre-existing (reproduces with the pinned binary), and the same two-implementations-of-one-concept shape as the variant operator table."
---

# A Boolean Variant writes as 1/0 on every target except x86-64

Found 2026-08-24 while gating
[[bug-a-not-on-an-integer-variant-answers-a-boolean]] — it is what was left in
the diff once that fix landed, and it is not part of it.

```pascal
var a: Variant;
begin
  a := True;  writeln('T: ', a);
  a := False; writeln('F: ', a);
end.
```

| built by | output |
| --- | --- |
| fpc 3.2.2 -Mobjfpc | `T: True` / `F: False` |
| pxx x86-64 | `T: True` / `F: False` |
| pxx i386 | `T: 1` / `F: 0` |
| pxx aarch64 | `T: 1` / `F: 0` |
| pxx arm32 | `T: 1` / `F: 0` |

**Reproduces with the PINNED binary**, so it predates today's variant work.

The tag is right on every target — `VarType(c)` answers the Boolean code
everywhere. Only the rendering differs, which puts the defect in whatever
writes a variant, not in what produced it.

## Where to look

`PXXWriteVariant` (`compiler/builtin/builtinheap.pas`) is the runtime renderer
the cross targets use; x86-64 has its own inline path. That is the same split
that produced the operator-table bug filed alongside this one — one concept,
two implementations, and the one nobody runs locally is the one that drifted.
So check whether the runtime one has a VT_BOOL arm at all before assuming a
subtle difference.

Worth a grep for the sibling while there: any other tag the two renderers
disagree about (VT_CHAR, VT_EMPTY, VT_DOUBLE formatting) is the same bug and
should be fixed in the same pass rather than filed three more times.

## Gate

Track A's, plus the four rows above matching fpc on x86-64, i386, arm32 and
aarch64. `test/test_variant_bitwise_and_not.pas` deliberately reads tags and
values instead of rendering Booleans, because of this; once this is fixed that
test can assert the rendered form directly.
