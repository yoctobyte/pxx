program test_enum_result_through_every_call_kind;
{ An ENUM-typed result keeps its identity through EVERY call kind, not just a
  direct one. `Writeln` of an enum prints the MEMBER NAME, and that is the whole
  instrument here: the identity is the only thing that separates `cGreen` from
  `1`, and losing it produces a plausible number rather than an error.

  A call node has no symbol and no field to ask, so the callee's Procs[] row is
  the only place an enum result's identity can live (ProcRetEnumId). Two
  independent halves were missing and NEITHER IS SUFFICIENT ALONE -- fixing only
  the first changed nothing at all, which is why this file exists rather than a
  one-row regression test:

    the READER   NodeEnumIdOf's call arm tested `= AN_CALL` and so answered for
                 one of the five call kinds. Now asks ASTNodeIsCall.
    the WRITER   the procedural-type signature path and the method-DECL path
                 never filled the column. A class method's row is filled again
                 when its BODY is parsed, so only a DECL-ONLY routine -- an
                 INTERFACE method -- stayed broken after the reader was fixed.
                 That asymmetry is why the `intf` row is here and is not
                 redundant with `meta`.

  Measured on pinned v403: four of these five rows printed `1`. Only `direct`
  was ever right, which is the control -- a fix that broke ordinary enum results
  would fail the first row and pass nothing.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  Found by a census of the ProcRet* columns, not by a report. }
{$mode delphi}
type
  TCol = (cRed, cGreen, cBlue);
  TF  = function(k: Integer): TCol;
  TMF = function(k: Integer): TCol of object;
  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function M(k: Integer): TCol;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    function M(k: Integer): TCol;
  end;
  TB = class
    class function CM(k: Integer): TCol; virtual;
  end;
  TBC = class of TB;

function Pick(k: Integer): TCol;
begin if k = 1 then Result := cGreen else Result := cBlue; end;
function TFoo.M(k: Integer): TCol;
begin if k = 1 then Result := cGreen else Result := cBlue; end;
class function TB.CM(k: Integer): TCol;
begin if k = 1 then Result := cGreen else Result := cBlue; end;

var fp: TF; mp: TMF; foo: TFoo; ifc: IFoo; mc: TBC;
begin
  fp := @Pick; foo := TFoo.Create; ifc := foo; mp := foo.M; mc := TB;
  Writeln('direct  ', Pick(1));      { the control -- always worked }
  Writeln('procvar ', fp(1));        { AN_CALL_IND }
  Writeln('methptr ', mp(1));        { AN_CALL_IND, method-pointer flavour }
  Writeln('intf    ', ifc.M(1));     { AN_INTF_CALL -- decl-only, no body to fill the row }
  Writeln('meta    ', mc.CM(1));     { AN_CLASS_VIRTUAL_CALL }
  { the other member, so a row that answers a CONSTANT rather than the value
    still fails }
  Writeln('other   ', fp(2));
end.
