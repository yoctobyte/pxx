{ argv on wasm32: ParamCount, ParamStr as an expression (the hidden frozen
  temp), and ArgStr into a managed string — the three shapes the backend has
  to lower separately.

  Compared against the NATIVE build, so only the cases where native is a usable
  oracle live here. Out of range and a longer-than-256-byte argument are both
  in argv_oob_slice.pas instead: the register targets disagree with each other
  about the first, and the native build CORRUPTS ITSELF on the second
  (bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp, found from this
  slice). The long argument comes back here once that is fixed.

  argv[0] is not printed either — it is `./prog` natively and `prog` under the
  node host, which is the harness's choice and not the backend's. That it is
  non-empty and that ParamCount excludes it are both still asserted. }
program argv_slice;
var
  i: Integer;
  s: string;
  n: Integer;
begin
  WriteLn('count=', ParamCount);
  ArgStr(0, s);
  if Length(s) > 0 then WriteLn('arg0=nonempty') else WriteLn('arg0=EMPTY');

  for i := 1 to ParamCount do
    WriteLn('expr[', i, ']=[', ParamStr(i), '] len=', Length(ParamStr(i)));

  for i := 1 to ParamCount do
  begin
    ArgStr(i, s);
    WriteLn('mgd[', i, ']=[', s, '] len=', Length(s));
  end;

  { The same index twice must give the same answer: a fetch that consumed
    something, or a buffer that was freed and read back, shows up here and
    nowhere else in this slice. }
  ArgStr(1, s);
  n := Length(s);
  ArgStr(1, s);
  if Length(s) = n then WriteLn('stable=yes') else WriteLn('stable=no');

  { Re-assigning a managed destination must RELEASE what it held rather than
    leak it or double-free it. Nothing here can observe a leak, but a
    double-free faults, so the loop is the assertion. }
  for i := 1 to 200 do
    ArgStr(1, s);
  WriteLn('reassign=[', s, ']');
end.
