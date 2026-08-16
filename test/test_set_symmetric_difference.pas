{ `><` = set symmetric difference (FPC/Delphi).
  bug-p-set-symmetric-difference-operator-not-supported: the operator did not
  lex, so every use died with "expected expression". Values below are what
  `fpc -O- -Mobjfpc` prints. }
program test_set_symmetric_difference;
type TD = (dMon,dTue,dWed,dThu,dFri,dSat,dSun); TDS = set of TD;
     TCS = set of char;
var ds, es: TDS; cs: TCS; d: TD; c: char; n, calls: integer;

function Side(const s: TDS): TDS; begin Inc(calls); Side := s; end;

procedure Show(const s: TDS);
begin
  for d := dMon to dSun do if d in s then write(Ord(d), ' ');
  writeln;
end;

begin
  ds := [dMon, dWed, dFri];
  es := [dWed, dThu];
  Show(ds >< es);
  Show(es >< ds);                       { commutative }
  Show(ds >< ds);                       { empty }
  Show(ds >< []);
  Show((ds >< es) >< es);               { involution: back to ds }

  { same precedence as + and -, left to right }
  Show(ds >< es + [dSun]);
  Show([dMon] + ds >< es);

  { operands are evaluated exactly once }
  calls := 0; ds := Side(ds) >< Side(es);
  writeln('calls=', calls);

  { char sets exercise the full 32-byte width, high bytes included }
  cs := ['a'..'e'] >< ['d'..'h', #200, #255];
  n := 0; for c := #0 to #255 do if c in cs then Inc(n);
  writeln('charcount=', n, ' a=', 'a' in cs, ' d=', 'd' in cs, ' h=', 'h' in cs,
          ' hi200=', #200 in cs, ' hi255=', #255 in cs);
end.
