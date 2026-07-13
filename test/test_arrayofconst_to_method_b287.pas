{ An `array of const` LITERAL passed to a METHOD: `TJSONData.DoError(msg, ['Nil', x])`.

  The plain-routine call path has always recognised a '[' in an array-of-const argument
  position; the METHOD call paths hand-rolled their own argument loops and did not, so the
  '[' was parsed as a SET and died on "set item must be one character".

  All the method call paths now go through one builder (GenMakeStaticMethodCall), which is
  the real fix: the duplication was the bug. }
program test_arrayofconst_to_method_b287;
uses sysutils;
type
  TC = class
    class procedure Log(const fmt: string; const args: array of const);
  end;
class procedure TC.Log(const fmt: string; const args: array of const);
begin
  writeln('  n=', Length(args), ' -> ', Format(fmt, args));
end;
begin
  writeln(Format('direct: %s = %d', ['answer', 42]));
  { the fpjson shape: an array-of-const LITERAL to a CLASS method }
  TC.Log('class: %s = %d', ['answer', 42]);
end.
