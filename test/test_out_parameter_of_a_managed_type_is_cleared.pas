program test_out_parameter_of_a_managed_type_is_cleared;
{ FPC finalizes a MANAGED `out` parameter on entry, and ONLY a managed one. pxx
  modelled `out` as a spelling of `var` at every parse site, so it cleared
  neither — which made the ordinal rows accidentally right and the managed rows
  wrong: a callee that assigns on only some paths handed the caller back its own
  previous value, with no way to tell.
  bug-a-an-out-parameter-of-a-managed-type-is-not-cleared

  The negative rows matter as much as the positive ones. `out v: Integer`,
  `out c: Char`, `out s: ShortString` and a record with NO managed fields must
  NOT be cleared — measured against fpc 3.2.2, they behave exactly like `var`
  there, so clearing them would be a divergence in the other direction.

  The Variant and managed-record rows arrived one ticket later
  (feature-a-finalize-an-out-variant-and-managed-record): neither has an
  empty-value LITERAL to assign, which is how the first three kinds were
  cleared, so they go through the finalize intrinsic instead. `outrec` keeps
  `n=3` on purpose — Finalize releases the MANAGED fields and leaves the
  unmanaged ones alone, which is the line between `out` and FillChar. }
{$mode objfpc}{$H+}
uses SysUtils;
type
  TDA  = array of Integer;
  TRecM = record name: AnsiString; n: Integer; end;   { managed — cleared }
  TRecU = record a, b: Integer; end;                  { unmanaged — must not be }
  IFoo = interface ['{11111111-2222-3333-4444-555555555555}'] function V: Integer; end;
  TFoo = class(TInterfacedObject, IFoo)
    function V: Integer;
    procedure MOut(out s: AnsiString);
    class procedure COut(out s: AnsiString);
  end;
function TFoo.V: Integer; begin Result := 7; end;
procedure TFoo.MOut(out s: AnsiString); begin end;
class procedure TFoo.COut(out s: AnsiString); begin end;

{ managed — cleared }
procedure OutS  (out s: AnsiString);  begin end;
procedure OutD  (out d: TDA);         begin end;
procedure OutI  (out f: IFoo);        begin end;
procedure OutV  (out v: Variant);     begin end;
procedure OutR  (out r: TRecM);       begin end;
{ managed, but ASSIGNED — the clear must not eat the assignment }
procedure OutSA (out s: AnsiString);  begin s := 'set'; end;
procedure OutVA (out v: Variant);     begin v := 'set'; end;
procedure OutRA (out r: TRecM);       begin r.name := 'set'; r.n := 9; end;
{ NOT managed — must behave exactly like var }
procedure OutInt(out v: Integer);     begin end;
procedure OutCh (out c: Char);        begin end;
procedure OutSS (out s: ShortString); begin end;
procedure VarInt(var v: Integer);     begin end;
procedure OutRU (out r: TRecU);       begin end;
{ shapes that exercise the parameter plumbing }
procedure TwoOut(out a, b: AnsiString; var c: AnsiString); begin b := 'B'; end;
procedure Mixed (x: Integer; out s: AnsiString; const y: AnsiString); begin end;
function  FOut  (out s: AnsiString): Integer; begin Result := 1; end;
procedure Host  (out s: AnsiString);
  procedure Inner; begin end;
begin Inner; end;
{ untyped `out` (QueryInterface's shape) — nothing to finalize, must not try }
procedure OutU(out x); begin end;

var
  s, a, b, c: AnsiString; d: TDA; f, g: IFoo; ff: TFoo;
  v: Integer; ch: Char; ss: ShortString; t: AnsiString; i, bad: Integer;
  vv: Variant; rm: TRecM; ru: TRecU;
begin
  s := 'x';  OutS(s);          WriteLn('str      [', s, ']');
  SetLength(d, 4); OutD(d);    WriteLn('dyn      ', Length(d));
  f := TFoo.Create; OutI(f);   WriteLn('intf     ', f = nil);
  vv := 'vv'; OutV(vv);        WriteLn('variant  [', vv, ']');
  rm.name := 'q'; rm.n := 3; OutR(rm);
                               WriteLn('rec      [', rm.name, '] ', rm.n);
  s := 'x';  OutSA(s);         WriteLn('assigned [', s, ']');
  vv := 'vv'; OutVA(vv);       WriteLn('varassn  [', vv, ']');
  rm.name := 'q'; rm.n := 3; OutRA(rm);
                               WriteLn('recassn  [', rm.name, '] ', rm.n);

  v := 42;   OutInt(v);        WriteLn('int      ', v);
  v := 42;   VarInt(v);        WriteLn('varint   ', v);
  ch := 'z'; OutCh(ch);        WriteLn('char     [', ch, ']');
  ss := 'y'; OutSS(ss);        WriteLn('shortstr [', ss, ']');
  ru.a := 1; ru.b := 2; OutRU(ru);
                               WriteLn('unmgdrec ', ru.a, ' ', ru.b);

  ff := TFoo.Create;
  s := 'x';  ff.MOut(s);       WriteLn('method   [', s, ']');
  s := 'x';  TFoo.COut(s);     WriteLn('classm   [', s, ']');
  a := 'A'; b := 'x'; c := 'C'; TwoOut(a, b, c);
                               WriteLn('twoout   [', a, '][', b, '][', c, ']');
  s := 'x';  Mixed(1, s, 'k'); WriteLn('mixed    [', s, ']');
  s := 'x';  i := FOut(s);     WriteLn('funcout  [', s, '] ', i);
  s := 'x';  Host(s);          WriteLn('nested   [', s, ']');
  v := 5;    OutU(v);          WriteLn('untyped  ', v);

  { ARC: the clear RELEASES the caller's reference, so a SECOND owner must
    survive it. Without the release this leaks; with a double release the second
    owner is freed under it and this reads freed memory. }
  bad := 0;
  for i := 1 to 2000 do
  begin
    s := 'payload-' + IntToStr(i);
    t := s;
    OutS(s);
    if t = '' then Inc(bad);
    f := TFoo.Create; g := f;
    OutI(f);
    if g.V <> 7 then Inc(bad);
    { the Variant and record clears release a reference too — t is the second
      owner of the same payload and must survive both }
    vv := t;      OutV(vv);
    if t = '' then Inc(bad);
    rm.name := t; OutR(rm);
    if t = '' then Inc(bad);
  end;
  WriteLn('survive  [', Copy(t, 1, 8), '] ', g.V, ' bad=', bad);
end.
