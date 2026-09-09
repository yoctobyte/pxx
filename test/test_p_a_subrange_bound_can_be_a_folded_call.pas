{ A SUBRANGE'S BOUNDS DO NOT HAVE TO BE NAMES EITHER.

  2026-09-05 widened the type-level subrange peek from LITERAL bounds to NAMED
  ones (`sat..sun`, `Lo..Hi`, `False..True`). The peek it installed was two
  tokens wide -- identifier, then `..` -- and deliberately so. This file is the
  next spelling out, and it is not hypothetical: FPC's own compiler writes

      TCGNonRefLoc = low(TCGLoc)..pred(LOC_CREFERENCE);      -- cgbase.pas:63

  which put three tokens between the identifier and the `..`, so the peek could
  not see it and `low` was reported as an unknown TYPE. cgbase is used by most
  of FPC's compiler (umbrella-pxx-compiles-fpc-itself).

  WHAT EACH HALF OF THIS FILE IS FOR:

  * The `array[...]` rows are the CONTROL and they are not new. That door has
    never had a peek -- it goes straight to ConstEvalOrdBound -- so it accepted
    every bound below before this change and accepts them now. They are here to
    assert the two doors give the SAME answer: the whole point of the fix is
    that nothing new had to learn to evaluate anything, and a type-declaration
    row that agreed with fpc while the array row disagreed would mean the fold
    had been duplicated rather than reached.
  * The named-bound rows are regression ballast for 2026-09-05 and say so.
  * The call-shaped rows in TYPE, VAR, RECORD FIELD and PARAMETER position are
    the rows that could not compile at all before this change.

  Every expected value was read off fpc 3.3.1 running this same source, and the
  PINNED compiler refuses the file outright, so it cannot pass for free.        }
program test_p_a_subrange_bound_can_be_a_folded_call;

type
  TE = (ea, eb, ec, ed, ee);

const
  KLO = 2;
  KHI = 7;

type
  { --- regression ballast: NAMED bounds, working since 2026-09-05 --- }
  TNamedEnum = eb..ed;
  TNamedInt  = KLO..KHI;
  TNamedBool = False..True;

  { --- the rows this change is about: CALL-SHAPED bounds --- }
  TCallLo   = low(TE)..pred(ec);      { ea..eb }
  TCallHi   = succ(ea)..high(TE);     { eb..ee }
  TCallOrd  = Ord(ea)..Ord(ee);       { 0..4, a cast-shaped bound }
  TCallMix  = low(TE)..ed;            { one call bound, one named }
  TCallMix2 = eb..high(TE);           { the other way round }

  { --- the SAME bounds through the array-index door, which never had a peek.
        These compiled before the change too; they are the control.       --- }
  TArrLo = array[low(TE)..pred(ec)] of Integer;
  TArrHi = array[succ(ea)..high(TE)] of Integer;

  { --- a RECORD FIELD and a nested type, both reached through ParseTypeKind
        rather than through the type-section naming path.                 --- }
  TRec = record
    f: low(TE)..pred(ec);
    g: succ(ea)..high(TE);
  end;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

{ A PARAMETER of a call-shaped subrange, through its NAME. The anonymous
  spelling -- `v: low(TE)..pred(ec)` -- is deliberately NOT here: fpc 3.3.1
  refuses it (`Type identifier expected`) while pxx accepts it, and us
  accepting what fpc rejects is not a defect, so it is not a row this file can
  assert parity on. Measured, not assumed. }
function TakesSub(v: TCallLo): Integer;
begin
  TakesSub := Ord(v);
end;

var
  ne: TNamedEnum; ni: TNamedInt; nb: TNamedBool;
  cl: TCallLo; ch: TCallHi; co: TCallOrd; cm: TCallMix; cm2: TCallMix2;
  al: TArrLo; ah: TArrHi;
  r: TRec;
  anon: low(TE)..pred(ec);

begin
  fails := 0;

  { --- ballast: named bounds --- }
  ne := ec; Chk('named enum bound',  Ord(ne), 2);
  ni := 5;  Chk('named int bound',   ni, 5);
  nb := True; Chk('named bool bound', Ord(nb), 1);

  { --- call-shaped bounds carry the right LOW and HIGH, which is the part a
        merely-parsing fix would get wrong: the bounds must reach the type, not
        just get consumed. Ord() on both ends of every one.              --- }
  Chk('Low(TCallLo)',  Ord(Low(TCallLo)),  Ord(ea));
  Chk('High(TCallLo)', Ord(High(TCallLo)), Ord(eb));
  Chk('Low(TCallHi)',  Ord(Low(TCallHi)),  Ord(eb));
  Chk('High(TCallHi)', Ord(High(TCallHi)), Ord(ee));
  Chk('Low(TCallOrd)',  Low(TCallOrd),  0);
  Chk('High(TCallOrd)', High(TCallOrd), 4);
  Chk('Low(TCallMix)',  Ord(Low(TCallMix)),  Ord(ea));
  Chk('High(TCallMix)', Ord(High(TCallMix)), Ord(ed));
  Chk('Low(TCallMix2)',  Ord(Low(TCallMix2)),  Ord(eb));
  Chk('High(TCallMix2)', Ord(High(TCallMix2)), Ord(ee));

  { --- THE CONTROL: the array door, same bounds, must agree exactly --- }
  Chk('Low(TArrLo) = Low(TCallLo)',   Ord(Low(TArrLo)),  Ord(Low(TCallLo)));
  Chk('High(TArrLo) = High(TCallLo)', Ord(High(TArrLo)), Ord(High(TCallLo)));
  Chk('Low(TArrHi) = Low(TCallHi)',   Ord(Low(TArrHi)),  Ord(Low(TCallHi)));
  Chk('High(TArrHi) = High(TCallHi)', Ord(High(TArrHi)), Ord(High(TCallHi)));

  { --- and they still INDEX --- }
  al[ea] := 11; al[eb] := 22;
  ah[eb] := 33; ah[ee] := 44;
  Chk('al[ea]', al[ea], 11);
  Chk('al[eb]', al[eb], 22);
  Chk('ah[eb]', ah[eb], 33);
  Chk('ah[ee]', ah[ee], 44);

  { --- values still store and read back in every position --- }
  cl := eb;  Chk('cl', Ord(cl), Ord(eb));
  ch := ee;  Chk('ch', Ord(ch), Ord(ee));
  co := 3;   Chk('co', co, 3);
  cm := ed;  Chk('cm', Ord(cm), Ord(ed));
  cm2 := ec; Chk('cm2', Ord(cm2), Ord(ec));
  r.f := ea; r.g := ed;
  Chk('r.f', Ord(r.f), Ord(ea));
  Chk('r.g', Ord(r.g), Ord(ed));
  anon := eb; Chk('anonymous var', Ord(anon), Ord(eb));
  Chk('TakesSub', TakesSub(eb), Ord(eb));

  { --- the ENUM IDENTITY survives a call-shaped bound. A subrange of an enum
        is stored as an integer PLUS the enum id; lose the id and WriteLn
        prints the ordinal instead of the member name, which no Ord() row
        above can see.                                                   --- }
  cl := ea;
  WriteLn('member=', cl);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('SUBCALL OK');
end.
