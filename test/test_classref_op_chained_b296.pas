{ A class-reference OPERATION chained after a value: `d.Self_.ClassName`,
  `(Data as TJSONArray).ClassType` (fcl-json's own suite).

  ClassName / ClassType / InheritsFrom are not methods, so the method path in the chained-
  selector loop never matched them -- and the selector was then simply DROPPED, because a
  member on a class-typed value that resolves to nothing falls through silently. The
  expression evaluated to the object pointer: it printed a NUMBER where a class name was
  expected, with no error at all. (The general form of that silent acceptance is filed as
  bug-pascal-member-access-on-pointer-silently-accepted.)

  An INSTANCE reaches its blob through AN_RTTIOF; a class reference IS the blob. A real member
  of that name on the class still wins. }
program test_classref_op_chained_b296;
type
  TB = class
    function Self_: TB;
  end;
  TD = class(TB) end;
function TB.Self_: TB; begin Result := Self; end;
var d: TD;
begin
  d := TD.Create;
  { a class-ref op CHAINED after a method-call result -- ParseClassRecordSelectors path }
  writeln(d.Self_.ClassName);
  writeln(d.Self_.InheritsFrom(TB));
end.
