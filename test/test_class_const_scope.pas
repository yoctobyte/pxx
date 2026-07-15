program test_class_const_scope;
{ Class consts are class-SCOPED, not unscoped globals
  (bug-pascal-class-const-visibility). Self-checking; the values below are
  FPC-differential (verified byte-identical against fpc {$mode objfpc}). }

const
  Size = 10;             { unit global — a class const of the same name must NOT clobber it }

type
  TA = class
  private const Max = 5;
  public
    function GetMax: Integer;    { bare Max -> TA's 5 }
  end;

  TB = class
  private const Max = 99;
  public
    function GetMax: Integer;    { bare Max -> TB's 99, NOT TA's }
  end;

  TC = class
  const Size = 777;
  public
    function GetSize: Integer;   { bare Size -> class const 777, not unit global 10 }
  end;

  TBase = class
  const Tag = 'base'; K = 42;
  end;

  TDer = class(TBase)            { inherits Tag / K from TBase }
  public
    function ShowK: Integer;
    function ShowTag: string;
  end;

function TA.GetMax: Integer;  begin Result := Max; end;
function TB.GetMax: Integer;  begin Result := Max; end;
function TC.GetSize: Integer; begin Result := Size; end;
function TDer.ShowK: Integer;   begin Result := K; end;      { inherited scalar class const in method }
function TDer.ShowTag: string;  begin Result := Tag; end;    { inherited string class const in method }

var
  a: TA; b: TB; c: TC; d: TDer;
  ok: Boolean;
begin
  a := TA.Create; b := TB.Create; c := TC.Create; d := TDer.Create;
  ok := True;

  { cross-class clobber: each class reads its OWN Max }
  if a.GetMax <> 5  then begin writeln('FAIL a.GetMax=', a.GetMax); ok := False; end;
  if b.GetMax <> 99 then begin writeln('FAIL b.GetMax=', b.GetMax); ok := False; end;

  { class const does not clobber a same-named unit global, and vice versa }
  if Size <> 10       then begin writeln('FAIL unit Size=', Size); ok := False; end;
  if c.GetSize <> 777 then begin writeln('FAIL c.GetSize=', c.GetSize); ok := False; end;

  { inheritance: a descendant method sees an ancestor's class const }
  if d.ShowK <> 42        then begin writeln('FAIL d.ShowK=', d.ShowK); ok := False; end;
  if d.ShowTag <> 'base'  then begin writeln('FAIL d.ShowTag=', d.ShowTag); ok := False; end;

  { qualified TClass.Const access (scalar + string), incl. up the parent chain }
  if TA.Max <> 5      then begin writeln('FAIL TA.Max=', TA.Max); ok := False; end;
  if TB.Max <> 99     then begin writeln('FAIL TB.Max=', TB.Max); ok := False; end;
  if TBase.K <> 42    then begin writeln('FAIL TBase.K=', TBase.K); ok := False; end;
  if TDer.K <> 42     then begin writeln('FAIL TDer.K=', TDer.K); ok := False; end;
  if TBase.Tag <> 'base' then begin writeln('FAIL TBase.Tag=', TBase.Tag); ok := False; end;

  if ok then writeln('CLASS CONST OK') else writeln('CLASS CONST FAIL');
end.
