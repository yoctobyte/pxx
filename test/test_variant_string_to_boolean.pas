program test_variant_string_to_boolean;
{ A Variant holding text converts to a Boolean by FPC's rule: the two keywords
  case-insensitively and WITHOUT trimming, else parse it as a number and test
  against zero, else raise.

  pxx used to raise for EVERY string, on the strength of a measurement that only
  covered the empty one -- '' does raise in FPC, and so does 'zz', but 'True'
  converts. So a program died on the exact spelling a Boolean arrives in from a
  config file or a query result.

  Each raising row is asserted as a RAISE, not skipped: refusing 'yes' is as much
  part of FPC's rule as accepting 'True', and a fix that made everything convert
  would pass a test that only checked the accepting half.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 agrees with all 21 rows. }
{$mode objfpc}{$H+}
uses variants, sysutils;
var
  v: Variant;
  fails: Integer;

procedure ChkVal(const what: string; want: Boolean);
var got: Boolean;
begin
  try
    got := v;
    if got <> want then
    begin
      writeln('FAIL ', what, ': got ', got, ' want ', want);
      Inc(fails);
    end;
  except
    on e: Exception do
    begin
      writeln('FAIL ', what, ': raised ', e.ClassName, ', wanted ', want);
      Inc(fails);
    end;
  end;
end;

procedure ChkRaise(const what: string);
var got: Boolean;
begin
  try
    got := v;
    writeln('FAIL ', what, ': got ', got, ', wanted a raise');
    Inc(fails);
  except
    on e: Exception do ;   { expected }
  end;
end;

begin
  fails := 0;

  { --- the two keywords, case-insensitive --- }
  v := 'True';  ChkVal('True',  True);
  v := 'true';  ChkVal('true',  True);
  v := 'TRUE';  ChkVal('TRUE',  True);
  v := 'False'; ChkVal('False', False);
  v := 'FaLsE'; ChkVal('FaLsE', False);

  { --- ...and NOT trimmed --- }
  v := ' true'; ChkRaise('leading space');
  v := 'true '; ChkRaise('trailing space');

  { --- numeric text, tested against zero --- }
  v := '1';     ChkVal('"1"',    True);
  v := '2';     ChkVal('"2"',    True);
  v := '-1';    ChkVal('"-1"',   True);
  v := '2.5';   ChkVal('"2.5"',  True);
  v := '0';     ChkVal('"0"',    False);
  v := '0.0';   ChkVal('"0.0"',  False);
  v := '-0';    ChkVal('"-0"',   False);

  { --- neither a keyword nor a number --- }
  v := '';      ChkRaise('empty');
  v := 'zz';    ChkRaise('zz');
  v := 'yes';   ChkRaise('yes');

  { --- non-string tags unchanged --- }
  v := 1;       ChkVal('int 1',   True);
  v := 0;       ChkVal('int 0',   False);
  v := 2.5;     ChkVal('dbl 2.5', True);
  v := 0.0;     ChkVal('dbl 0.0', False);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
