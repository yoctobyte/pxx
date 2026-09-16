{ MUST BE REFUSED. The positive control for
  test_parenless_call_to_an_overloaded_name.pas.

  That fixture teaches both parenless call doors to look past FindProc's
  representative for a parameterless member of a same-named set. The way that
  change could be WRONG is by accepting a bare name whose set has no
  parameterless member at all -- i.e. turning a real arity error into a silent
  call with garbage arguments. Every row of the positive fixture would still
  pass if the doors had simply been made to accept anything, so without this
  file that suite cannot fail in the dangerous direction.

  Two declarations, both taking parameters, neither callable bare. `Only(r)` is
  correct and is deliberately absent: this program must not compile. }
program test_parenless_call_to_an_overloaded_name_still_needs_one;

type
  TRec = record a: LongInt; end;

function Only(const st: TRec): LongInt;
begin Only := st.a; end;

function Only(k: LongInt): LongInt;
begin Only := k; end;

var n: LongInt;
begin
  n := Only;          { no parameterless member exists -- refuse }
  WriteLn(n);
end.
