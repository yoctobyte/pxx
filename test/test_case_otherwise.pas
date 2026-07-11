program test_case_otherwise;
{ `otherwise` (ISO 10206; FPC default mode) as soft-keyword synonym of `else`
  in case statements. Also checks `otherwise` stays usable as an ordinary
  identifier outside the case branch-start position. }
var
  i: Integer;
  otherwise: Integer;  { soft keyword: fine as a variable name }
begin
  otherwise := 7;

  { otherwise-branch NOT taken }
  i := 1;
  case i of
    1: writeln('one');
    otherwise writeln('other ', otherwise);
  end;

  { otherwise-branch taken; implicit statement list up to end }
  i := 5;
  case i of
    1: writeln('one');
    2, 3: writeln('two-three');
    otherwise
      writeln('other ', otherwise);
      writeln('still-other');
  end;
end.
