{ Class-NESTED types, referenced by their qualified name: `TOuter.TInner` (b348, tdefault8).

  A `type` section inside a class body was already parsed, and its members registered — but
  as GLOBAL aliases under their BARE name, because pxx deliberately does not scope
  class-local types. So `TInner` resolved and `TOuter.TInner` did not: the qualified
  spelling, which is the one real FPC code writes, failed with "unknown type".

  The qualifier only disambiguates the PARSE, not the lookup, so it is stripped — the same
  thing the unit-qualified path (`sockets.Tin6_addr`) already did.

  SizeOf() needed the same treatment: it has its own hand-rolled type dispatch, so
  `var r: TOuter.TInner` worked while `SizeOf(TOuter.TInner)` still died on the '.'. A
  half-working feature is worse than an absent one.

  Also covers TSysCharSet (tset4), which was simply missing from SysUtils. }
program test_nested_class_type_b348;
{$mode objfpc}
uses SysUtils;

type
  TOuter = class
  public type
    TInner = record
      a, b: LongInt;
    end;
    TPair = record
      x: TInner;
      tag: LongInt;
    end;
  end;

var
  r: TOuter.TInner;
  p: TOuter.TPair;
  cset: TSysCharSet;
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Int64);
begin
  if got = want then writeln('ok   ', what, ' = ', got)
  else begin writeln('FAIL ', what, ' = ', got, ' (want ', want, ')'); fails := fails + 1; end;
end;

begin
  fails := 0;

  r.a := 3; r.b := 4;
  Check('qualified nested record, fields', r.a + r.b, 7);

  { a nested type used INSIDE another nested type }
  p.x.a := 10; p.x.b := 20; p.tag := 7;
  Check('nested type within a nested type', p.x.a + p.x.b + p.tag, 37);

  Check('SizeOf(TOuter.TInner)', SizeOf(TOuter.TInner), 8);

  { TSysCharSet — the RTL type tset4 needed }
  cset := [];
  Include(cset, 'a');
  Include(cset, 'z');
  Check('TSysCharSet member present', Ord('z' in cset), Ord(True));
  Check('TSysCharSet member absent', Ord('b' in cset), Ord(False));

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
