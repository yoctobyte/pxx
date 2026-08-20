program test_cast_deref_pointer_field;
{ An INLINE typed-pointer cast must not lose a pointer FIELD's pointee type.

  `PRec(raw)^.n^` typed the second `^` from the ORIGINAL cast's alias — the
  record PRec points at — instead of from the field `n` the `^` is actually
  applied to. The deref still happened, so the bytes were right and only the
  TAG was wrong: Writeln printed the string's heap address as an integer.

  Three things made it invisible, and all three are asserted here:
   - the same chain with the cast parked in a VARIABLE was correct, so one
     expression had two spellings that disagreed (rows 2 vs 3);
   - a `^Int64` field through the same cast "worked", because the wrong tag
     happened to match what the field really was (row 4);
   - one level of deref was always fine (row 5).
  Rows 3 and 7 are the ones that were wrong. Row 7 also shows it was never
  about casting from untyped Pointer: casting an already-correct PRec to PRec
  broke it too.

  Every row diffed against FPC 3.2.2.
  bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped }
type
  PStr = ^string;
  PInt = ^Int64;
  TRec = record k: Int64; n: PStr; m: PInt; end;
  PRec = ^TRec;
  TOut = record r: PRec; end;
var r: TRec; s: string; v: Int64; raw: Pointer; p: PRec; o: TOut;
begin
  s := 'hello'; v := 99; r.k := 42; r.n := @s; r.m := @v; raw := @r; o.r := @r;
  p := PRec(raw);
  Writeln('2 var  n^     : ', p^.n^);
  Writeln('3 cast n^     : ', PRec(raw)^.n^);
  Writeln('4 cast m^     : ', PRec(raw)^.m^);
  Writeln('5 cast k      : ', PRec(raw)^.k);
  Writeln('6 field  n^   : ', o.r^.n^);
  Writeln('7 nocast p^n^ : ', PRec(p)^.n^);
end.
