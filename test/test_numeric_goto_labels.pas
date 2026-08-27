program test_numeric_goto_labels;
{ Standard Pascal spells a label as a DIGIT SEQUENCE; FPC accepts that and the
  identifier form. pxx accepted only identifiers — `label 10;` died with
  `unexpected token`. bug-a-numeric-goto-labels-are-not-supported

  The parsing hazard the ticket named is row `c`: a statement-position `10:` in
  a `case` arm is a case LABEL, not a goto label, and the two must not be
  confused. }
{$mode objfpc}

label 10, 20;

{ numeric labels inside a ROUTINE, with a BACKWARD jump as the loop }
function CountTo(n: Integer): Integer;
label 1, 99;
var i, acc: Integer;
begin
  i := 0; acc := 0;
1:
  Inc(i);
  acc := acc + i;
  if i >= n then goto 99;
  goto 1;
99:
  CountTo := acc;
end;

{ the identifier form still works, in the same routine as numeric ones }
function Mixed: Integer;
label done, 7;
var r: Integer;
begin
  r := 0;
  goto 7;
  r := 100;
7:
  r := r + 5;
  goto done;
  r := 200;
done:
  Mixed := r;
end;

var k: Integer;
begin
  k := 1;
  goto 10;
  WriteLn('a NOT REACHED');
10:
  WriteLn('a ', k);
  { a numeric CASE label is not a goto label }
  case k of
    10: WriteLn('b case-ten');
    1: WriteLn('b case-one');
  end;
  WriteLn('c ', CountTo(4));
  WriteLn('d ', Mixed);
  if k = 1 then goto 20;
  WriteLn('e NOT REACHED');
20:
  WriteLn('e done');
  WriteLn('OK');
end.
