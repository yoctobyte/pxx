{ Owned-or-borrowed verdicts for a class result, read off the body by
  ClassifyProcResultFresh (pasparser_proc.inc) and printed by
  PXXDBG=p.fresh. TRUE only when every returned value was minted for the
  caller; anything borrowed, or a body with one borrowed path, is FALSE.
  The row diffs these lines against test_result_fresh_verdicts.expected. }
program test_result_fresh_verdicts;
type
  TA = class
    v: Integer;
    other: TA;
    items: array[0..3] of TA;
    function Fresh: TA;
    function Me: TA;
    function Via: TA;
    function ViaBorrowed: TA;
    function Fld: TA;
    function Element(i: Integer): TA;
    function Named: TA;
    function NamedSelf: TA;
    function Mixed: TA;
    function ViaLocal: TA;
    function OrNil: TA;
  end;

function MakeA: TA;
begin
  Result := TA.Create;
end;

function PassThrough(a: TA): TA;
begin
  Result := a;
end;

function TA.Fresh: TA;
begin
  Result := TA.Create;
end;

function TA.Me: TA;
begin
  Result := Self;
end;

function TA.Via: TA;
begin
  Result := MakeA;
end;

function TA.ViaBorrowed: TA;
begin
  Result := PassThrough(Self);
end;

function TA.Fld: TA;
begin
  Result := other;
end;

function TA.Element(i: Integer): TA;
begin
  Result := items[i];
end;

function TA.Named: TA;
begin
  Named := TA.Create;
end;

function TA.NamedSelf: TA;
begin
  NamedSelf := Self;
end;

function TA.Mixed: TA;
begin
  if v > 0 then Exit(Self);
  Result := TA.Create;
end;

function TA.ViaLocal: TA;
var t: TA;
begin
  t := TA.Create;
  Result := t;
end;

function TA.OrNil: TA;
begin
  if v > 0 then Exit(nil);
  Result := TA.Create;
end;

var a: TA;
begin
  a := TA.Create;
  WriteLn(a.v);
end.
