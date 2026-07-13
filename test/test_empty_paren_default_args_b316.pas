{ `obj.F()` — EMPTY parens on a method whose parameters ALL have defaults.

  FPC accepts it, and fcl-json's own test suite writes `J.FormatJSON()` that way. pxx handed
  the `)` straight to ParseExpr and reported "expected expression" — the argument loop had a
  case for trailing defaults AFTER at least one argument, but none for ZERO arguments.

  A method with NO parameters at all always worked, because the loop simply never ran, which
  is why this went unnoticed.

  Six method-call argument loops needed it (fat-pointer, constructor, selector, ...); they
  are separate copies of the same dispatch. Expected output is FPC's.

  Found in feature-pascal-corpus-fpjson (wall at testjsondata.pp:3042). }
program test_empty_paren_default_args_b316;
{$mode objfpc}{$H+}
uses sysutils;
type
  TFmtOpt = (foA, foB);
  TOpt = set of TFmtOpt;
  TBox = class
    function Fmt(Options: TOpt = []; IndentSize: Integer = 2): string;
    function Plain: string;
  end;
function TBox.Fmt(Options: TOpt = []; IndentSize: Integer = 2): string;
begin Fmt := 'fmt' + IntToStr(IndentSize); end;
function TBox.Plain: string;
begin Plain := 'plain'; end;
var B: TBox;
begin
  B := TBox.Create;
  writeln(B.Fmt);          { no parens }
  writeln(B.Fmt());        { EMPTY parens — all params defaulted }
  writeln(B.Fmt([foA], 1));
  writeln(B.Plain());      { EMPTY parens on a paramless method }
  B.Free;
end.
