---
track: A
prio: 40
type: bug
blocked-by: []
status: done
summary: "`writeln(v)` with v a Boolean Variant prints True/False on x86-64 and 1/0 on i386, arm32 and aarch64. Same source, same program, different output per target -- and the 1/0 form is not what FPC prints either. Pre-existing (reproduces with the pinned binary), and the same two-implementations-of-one-concept shape as the variant operator table."
owner: claude-A
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

## FIXED 2026-08-24 (claude-A)

`PXXWriteVariant` (`compiler/builtin/builtinheap.pas`) folded VT_BOOL in with
the integer tags:

```pascal
if (tag = 1) or (tag = 2) or (tag = 4) then  { VT_INT / VT_INT64 / VT_BOOL }
begin
  iv := PWord(Int64(v) + 8)^;
  write(iv);
end
```

and its own header claimed it "mirrors EmitWriteVariant (x86-64)", which has a
`True`/`False` arm. The comment described the intent; the code did something
else, and nobody diffed them because x86-64 was right. Split out as its own arm
— the Python spelling is the same word, so one arm serves both frontends.

### What the sibling grep found, which is the part worth recording

The ticket said to grep for the other tags the two renderers might disagree
about rather than fix one and file three more. Measured across **bool, integer,
negative integer, double, char and string** on x86-64 / i386 / aarch64 /
arm32 against `fpc 3.2.2 -Mobjfpc -O1`: **Boolean was the only one.** After
this fix all four targets produce output identical to FPC's, line for line.

Two tags are deliberately still unmirrored, and that is not drift:

- **VT_EMPTY** — x86-64 writes `None`, the runtime writes nothing. FPC writes
  nothing for a cleared Variant and **raises** for `Null`, so x86-64's spelling
  is the contested one. Copying it here would have spread a rendering that is
  probably wrong to three more targets. That is
  [[bug-a-a-null-variant-renders-as-none-in-pascal]], and it now settles in one
  place for every target when it is answered.
- **VT_OBJECT** — x86-64 writes `<object>` as a debugging placeholder; FPC
  raises. Same reasoning.

Both are stated in `PXXWriteVariant`'s header so the next reader does not
"finish the mirror" without noticing they are open questions.

### Found in passing, not folded in

`VarClear` is undefined — `VarClear(v)` is `error: undefined variable`, though
FPC accepts it and prints an empty rendering afterwards. Filed as
[[bug-a-varclear-is-undefined]]; it is a missing library entry point, not a
renderer defect, and it is why the empty-slot row could not be measured from
Pascal at all.

### Verified

`test/test_variant_writes_every_tag.pas`, wired into `test-core`. It asserts
the whole OUTPUT STREAM rather than printing `ALL OK`, because the rendering is
the thing under test: `True|False|42|-7|1.25|q|hey|`. Identical under fpc 3.2.2
and under pxx on x86-64, i386, aarch64 and arm32. NilPy re-measured against
CPython (`print(True)`, `print(False)`, a Boolean expression, a comparison
result): unchanged, all four rows.

Self-host fixedpoint converged in one round; `tools/gate.sh quick` GREEN.

## Gate

`make compiler/pascal26` converged + the seven-row rendering diff on four
targets against FPC + the NilPy re-measure + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit 3bf667e92.
