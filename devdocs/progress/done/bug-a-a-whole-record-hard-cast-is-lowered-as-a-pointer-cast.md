---
slug: bug-a-a-whole-record-hard-cast-is-lowered-as-a-pointer-cast
track: A
prio: 65
status: done
commit: PENDING-COMMIT
---

# `q := TQ(r)` segfaults; `q.x := TQ(r).x` does not

```pascal
type TR = record a, b: Integer; end;
     TQ = record x: Int64; end;
var r: TR; q: TQ;
begin
  r.a := 1; r.b := 2;
  WriteLn(TQ(r).x);   { 8589934593 — correct }
  q := TQ(r);         { SEGFAULT }
end.
```

A hard cast between two same-size records is an in-place reinterpret; FPC prints
`8589934593` for both. PXX got the field read right and crashed on the
assignment — the *simpler* of the two spellings.

## The double case

The record-cast arm builds an `AN_PTR_CAST` tagged `tyPointer`, then, **only if
a `.` follows**, rebuilds it as `AN_DEREF(AN_ADDR(operand))` tagged `tyRecord`
so field offsets resolve against the cast's type. That rebuild is the value
reinterpret. Without a trailing accessor it never ran, so `TQ(r)` stayed a
POINTER — and `q := <pointer>` into a record variable is a record COPY from the
address r's first eight bytes happened to spell. On this test that address is
`$0000000200000001`. It is not a wild value; it is r's own contents read as an
address, which is why it is reliably a segfault rather than an occasional one.

`devdocs/dev/normalise-dont-special-case.md`, seventh time this session: one
construct reachable through two shapes, the transform attached to the shape with
the accessor, and the bare shape left on the path that was wrong. The fix is the
condition, not a new branch — the rebuild now also fires when the operand's
static type is a record:

```pascal
if (CurTok.Kind = tkDot) or
   ((CurTok.Kind <> tkCaret) and
    (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord)) then
```

`^` is excluded deliberately: `PR(pp)^` must keep dereferencing the pointer
VALUE. That is the one shape where the pointer reading is the right one, and it
is pinned by a row in the test.

## Verification

`test/test_whole_record_hard_cast.pas`, byte-identical to
`fpc 3.2.2 -Mobjfpc -O1`:

```
assign 8589934593        the crashing shape
field  8589934593        the shape that worked, kept as the control
lvalue 7 0               TQ(r).x := 7 writes through the cast
ptr    7                 PR(pp)^ still derefs the pointer value
p->i   67305985          packed 4xByte record -> Integer record
i->p   4 3 2 1           and back, so the byte order is pinned both ways
b->q   578437695752307201  8-byte array record -> Int64 record
byref  16909060          a cast as a const parameter
call   1                 a cast of a FUNCTION RESULT (no addressable operand)
```

The last two rows exist because the fix takes the operand's ADDRESS: a temporary
and a by-reference argument are the two operands that might not have one.

Found by the type-conversion/cast differential family.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.
