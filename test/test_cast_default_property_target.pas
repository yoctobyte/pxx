program test_cast_default_property_target;
{$mode objfpc}{$H+}
{ A DEFAULT property, indexed, as an assignment TARGET, through a cast.

  ParseClassRecordSelectors' default-property arm always built the GETTER --
  it never asked whether the `[` was a target, which the NAMED-property arm
  ~200 lines above it has asked since it was written. So the cast arm handed
  it `[3] := 206`, got a CALL back, the caller took that for a method-call
  statement, and the leftover `:= 206` hit "cannot assign to the result of a
  function call" at ParseStatementAST's exit. The SAME property spelled with
  its name -- TDerived(b).Items[3] := 206 -- stored 206, because that spelling
  reaches the named arm.

  The `as` spelling failed differently and worse: IR_UNSUPPORTED, an internal
  error rather than a diagnostic. Both cast spellings hand their `[` to the
  same walker, so both are fixed by the one arm.

  The virtual rows are the ones that would pass on a broken dispatch: SetIt
  multiplies by 10, so a value that arrives unmultiplied proves the ABSTRACT
  base was called rather than the override.
  bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target }
type
  TBase = class end;
  TDerived = class(TBase)
    fItems: array[0..3] of Integer;
    function GetItem(i: Integer): Integer;
    procedure SetItem(i, v: Integer);
    property Items[i: Integer]: Integer read GetItem write SetItem; default;
  end;
  TVBase = class
    function GetIt(i: Integer): Integer; virtual; abstract;
    procedure SetIt(i, v: Integer); virtual; abstract;
  end;
  TVImpl = class(TVBase)
    fI: array[0..3] of Integer;
    function GetIt(i: Integer): Integer; override;
    procedure SetIt(i, v: Integer); override;
    property Items[i: Integer]: Integer read GetIt write SetIt; default;
  end;
function TDerived.GetItem(i: Integer): Integer; begin Result := fItems[i]; end;
procedure TDerived.SetItem(i, v: Integer); begin fItems[i] := v; end;
function TVImpl.GetIt(i: Integer): Integer; begin Result := fI[i]; end;
procedure TVImpl.SetIt(i, v: Integer); begin fI[i] := v * 10; end;
var
  d: TDerived; b: TBase;
  vi: TVImpl; vb: TVBase;
begin
  d := TDerived.Create; b := d;
  d[3] := 200;                    WriteLn('nocast=', d.fItems[3]);
  TDerived(b)[3] := 206;          WriteLn('cast=', d.fItems[3]);
  (b as TDerived)[3] := 207;      WriteLn('ascast=', d.fItems[3]);
  TDerived(b).Items[3] := 208;    WriteLn('named=', d.fItems[3]);
  TDerived(b)[1 + 2] := 209;      WriteLn('exprsub=', d.fItems[3]);
  WriteLn('readback=', TDerived(b)[3], ' ', (b as TDerived)[3]);
  vi := TVImpl.Create; vb := vi;
  TVImpl(vb)[2] := 7;             WriteLn('virt=', vi.fI[2]);
  (vb as TVImpl)[2] := 8;         WriteLn('virtas=', vi.fI[2]);
end.
