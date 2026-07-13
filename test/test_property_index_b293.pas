{ The property `index` specifier: `property Strict: Boolean index joStrict read GetO write SetO`.

  A COMPILE-TIME constant handed to the accessor as its first argument, so several properties
  can share one getter/setter pair. Distinct from an INDEXED property, whose index is a
  runtime subscript. fcl-json's scanner declares its options this way. }
program test_property_index_b293;
type
  TOpt = (oStrict, oUTF8, oComments);
  TC = class
  private
    FOpts: array[0..2] of Boolean;
    function GetO(AIndex: Integer): Boolean;
    procedure SetO(AIndex: Integer; AValue: Boolean);
  public
    { several properties sharing ONE getter/setter, told apart by a CONSTANT index }
    property Strict:   Boolean index 0 read GetO write SetO;
    property UseUTF8:  Boolean index 1 read GetO write SetO;
    property Comments: Boolean index 2 read GetO write SetO;
  end;
function TC.GetO(AIndex: Integer): Boolean;
begin
  writeln('  [get idx=', AIndex, ']');
  Result := FOpts[AIndex];
end;
procedure TC.SetO(AIndex: Integer; AValue: Boolean);
begin
  writeln('  [set idx=', AIndex, ' -> ', AValue, ']');
  FOpts[AIndex] := AValue;
end;
var c: TC;
begin
  c := TC.Create;
  c.Strict := True;
  c.Comments := True;
  writeln('Strict   = ', c.Strict);
  writeln('UseUTF8  = ', c.UseUTF8);
  writeln('Comments = ', c.Comments);
end.
