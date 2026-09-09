{ The four Classes containers that FPC gives a GetEnumerator, exercised through
  BOTH doors.

  WHY BOTH DOORS AND NOT JUST for-in: tenumerators1.pp of the FPC testsuite does
  not write a for-in loop at all. It declares `Enumerator: TStringsEnumerator`
  and drives MoveNext/Current by hand, so the enumerator's TYPE NAME and its
  manual protocol are part of the surface we owe, not an implementation detail
  we may choose differently. A fixture that only wrote `for S in L` would pass
  with an enumerator of any name and any shape.

  WHAT WAS MISSING AND WHY IT READ AS A FRONTEND BUG. for-in over a TStrings sat
  in the conformance skip list for months as an enumerator-SELECTION gap. The
  selection mechanism was fixed 2026-09-07 -- a container carrying both a
  GetEnumerator and an `operator enumerator` now chooses by the loop variable's
  type -- and tforin24 STILL failed, because TStrings declared no GetEnumerator
  at all. There was nothing for the selection to select, so the test file's own
  object-yielding `operator enumerator` took both loops and printed garbage for
  the String one. A MISSING DECLARATION AND A WRONG CHOICE PRESENT IDENTICALLY
  at the call site; only reading the RTL separated them.

  The `hand` rows are the ones that would fail if an enumerator were renamed or
  given a different protocol; the `forin` rows are the ones that would fail if
  GetEnumerator stopped being found. Neither subsumes the other.

  Expected output is fpc 3.2.2's, in full.

  The COMPONENT rows are here for a different reason from the other three: they
  burn no conformance row today, because tenumerators1 also wants TCollection /
  TCollectionItem / TCollectionEnumerator, which this RTL does not have at all.
  They are verified HERE rather than by that row, so the surface is not
  unmeasured while it waits for TCollection. }
program lib_classes_enumerators;
{$mode objfpc}{$H+}
uses Classes, SysUtils;

var
  sl: TStringList;
  st: TStrings;
  se: TStringsEnumerator;
  l: TList;
  le: TListEnumerator;
  fp: TFPList;
  fe: TFPListEnumerator;
  co, ch: TComponent;
  ce: TComponentEnumerator;
  s: string;
  p: Pointer;
  c: TComponent;
  i: Integer;
begin
  { ---- TStrings ---- }
  sl := TStringList.Create;
  sl.Add('one'); sl.Add('two'); sl.Add('three');
  st := sl;
  se := st.GetEnumerator;
  while se.MoveNext do WriteLn('strings hand  ', se.Current);
  se.Free;
  for s in st do WriteLn('strings forin ', s);
  WriteLn('strings empty ', TStringList.Create.GetEnumerator.MoveNext);

  { ---- TList ---- }
  l := TList.Create;
  l.Add(Pointer(11)); l.Add(Pointer(22)); l.Add(Pointer(33));
  le := l.GetEnumerator;
  while le.MoveNext do WriteLn('list    hand  ', PtrInt(le.Current));
  le.Free;
  for p in l do WriteLn('list    forin ', PtrInt(p));

  { ---- TFPList: a DISTINCT enumerator type, not TList's ---- }
  fp := TFPList.Create;
  fp.Add(Pointer(44)); fp.Add(Pointer(55));
  fe := fp.GetEnumerator;
  while fe.MoveNext do WriteLn('fplist  hand  ', PtrInt(fe.Current));
  fe.Free;
  for p in fp do WriteLn('fplist  forin ', PtrInt(p));

  { ---- TComponent: iterates the components it OWNS ---- }
  co := TComponent.Create(nil);
  for i := 1 to 3 do
  begin
    ch := TComponent.Create(co);
    ch.Name := 'Child' + IntToStr(i);
  end;
  ce := co.GetEnumerator;
  while ce.MoveNext do WriteLn('comp    hand  ', ce.Current.Name);
  ce.Free;
  for c in co do WriteLn('comp    forin ', c.Name);
  WriteLn('comp    count ', co.ComponentCount);
end.
