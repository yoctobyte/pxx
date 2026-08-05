program test_index_getter_string_property;
{ Regression: indexing a STRING-returning call result — which is what a
  getter-backed string property lowers to.

  IRLowerAddress accepted a call in address position only for tyRecord/tyVariant
  (the RetViaHiddenDest kinds), so a string-returning call fell through to the
  IR_UNSUPPORTED tail: `c.GetS[1]`, and therefore `c.PG[1]` for a property whose
  read specifier is a getter, refused to compile with "frontend could not lower
  AST node (kind 8)".

  The ticket framed it as property-specific. It is not: `c.GetS[1]` — indexing
  any METHOD call result — failed identically, while a plain function call
  already worked, which is what made it look like a property bug. For a managed
  string the call's value is the HANDLE, and a handle is exactly what an index
  base wants, so lowering the call gives the right base.
  Output verified byte-identical to FPC.
  bug-p-index-getter-backed-string-property }
type
  TC = class
  private
    FS: string;
    function GetS: string;
    function GetIdx(i: Integer): string;
  public
    property PF: string read FS;
    property PG: string read GetS;
    property PI[i: Integer]: string read GetIdx;
  end;
function TC.GetS: string; begin GetS := FS; end;
function TC.GetIdx(i: Integer): string; begin GetIdx := 'wxyz'; end;
function Plain: string; begin Plain := 'abc'; end;
var c: TC; i: Integer;
begin
  c := TC.Create; c.FS := 'hello';
  writeln(c.PF[1]);         { field-backed, always worked }
  writeln(c.PG[1]);         { getter-backed — the bug }
  writeln(c.PG[5]);         { last char }
  writeln(c.GetS[2]);       { method call directly }
  writeln(Plain[1]);        { bare name }
  writeln(Plain()[2]);      { explicit call }
  writeln(c.PI[0][3]);      { indexed property, then char index }
  for i := 1 to Length(c.PG) do write(c.PG[i]);
  writeln;
  writeln(Length(c.PG), ' ', c.PG);
  writeln('OK');
end.
