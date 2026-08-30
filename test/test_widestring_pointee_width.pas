{ A pointer to a managed string keeps the POINTEE's element width, at every
  place a pointer can be held. Enumerated by the ENTITY holding the pointer,
  because that is what decides which carrier answers -- a symbol, a record
  field, an array element, an array TYPE's element, a call result of each of
  the four call shapes, and a parameter.

  ASCII payload on purpose: it makes the two widths differ by exactly the
  factor 2, so a wrong answer is 8 rather than a subtly wrong 5. FPC 3.2.2 is
  the oracle for every line -- it prints 4 throughout.
  feature-unicodestring-model }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
{$define PXX_WIDE_PAYLOAD}
program WidePointeeWidth;
type
  PW = ^WideString;
  TArr = array[0..1] of PW;
  TRec = record
    p: PW;
    function GetP: PW;
  end;
  IHolder = interface
    function GetP: PW;
  end;
  TBase = class(TInterfacedObject, IHolder)
    q: PW;
    function GetP: PW; virtual;
  end;
  TDeriv = class(TBase)
  end;

var
  w: WideString;
  q: PW;
  r: TRec;
  inl: array[0..1] of PW;
  nam: TArr;
  b: TBase;
  d: TDeriv;
  ih: IHolder;

function TRec.GetP: PW;
begin
  Result := p;
end;

function TBase.GetP: PW;
begin
  Result := q;
end;

function PlainGetP: PW;
begin
  Result := q;
end;

procedure TakeP(z: PW);
begin
  WriteLn('param     ', Length(z^));
end;

begin
  w := 'abcd';
  q := @w;
  r.p := @w;
  inl[0] := @w;
  nam[1] := @w;
  b := TBase.Create; b.q := @w;
  d := TDeriv.Create; d.q := @w;
  ih := b;
  WriteLn('symbol    ', Length(q^));
  WriteLn('field     ', Length(r.p^));
  WriteLn('inlinearr ', Length(inl[0]^));
  WriteLn('namedarr  ', Length(nam[1]^));
  WriteLn('plainres  ', Length(PlainGetP^));
  WriteLn('recmeth   ', Length(r.GetP^));
  WriteLn('virtmeth  ', Length(d.GetP^));
  WriteLn('intfmeth  ', Length(ih.GetP^));
  TakeP(q);
end.
