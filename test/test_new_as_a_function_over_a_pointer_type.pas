program test_new_as_a_function_over_a_pointer_type;
{ `New` has two spellings in FPC and pxx had one.

    New(p)      statement — allocate SizeOf(p^) and store it into p
    p := New(P) expression — same allocation, handed back as the value

  Only the statement form existed (it lives in the statement parser), so the
  expression form came out as `undefined variable (New)` — which is what
  rtl-generics' Generics.Defaults writes:
  `Result := New(PSpoofInterfacedTypeSizeObject)`.

  Both spellings are asserted here over the same types, because the point is
  that they agree: a record pointee (size from the record) and a scalar pointee
  (size from the type). The expression arm is additionally guarded on there
  being no user `New` proc or variable in scope and on the argument NAMING a
  pointer type alias, so a program with its own New keeps it — that guard is not
  exercisable from this file (a user New here would shadow the intrinsic for
  every line of it) and is asserted by the compiler's own sources instead.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode delphi}

type
  TRec = record a, b: Int64; end;
  PRec = ^TRec;
  PInt = ^Integer;

var
  p, q: PRec;
  n: PInt;
begin
  { expression form — the one that was missing }
  p := New(PRec);
  p^.a := 3; p^.b := 4;

  { statement form — must keep working, and agree }
  New(q);
  q^.a := 5; q^.b := 6;

  WriteLn('rec    : ', p^.a, ' ', p^.b, ' ', q^.a, ' ', q^.b);

  { a scalar pointee takes its size from the TYPE, not from a record }
  n := New(PInt);
  n^ := 99;
  WriteLn('scalar : ', n^);

  { the block is a real heap block: it survives, and Dispose takes it back }
  Dispose(n); Dispose(q); Dispose(p);
  WriteLn('done   : ok');
end.
