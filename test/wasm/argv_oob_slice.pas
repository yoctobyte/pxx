{ ParamStr where the DIFF against native cannot go: out-of-range indices, and
  an argument longer than a frozen local.

  Both are wasm-only for the same underlying reason — the native x86-64 build
  is not a usable oracle for either.

  * Out of range: x86-64 guards (EmitArgvToString compares the index against
    argc unsigned and yields '') but riscv32 does not, so there is no single
    "the register targets do" to diff against. This backend guards, so the
    expectation below is x86-64's.

  * A long argument: x86-64 copies the full strlen into a 264-byte frozen
    local with no clamp and smashes the adjacent frame slot
    (bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp). Diffing
    against a build that corrupts itself would only ever fail, so the long
    case is asserted here against a written-out expectation instead. }
program argv_oob_slice;
var s: string; i: Integer; n: Integer;
begin
  WriteLn('oob_expr=[', ParamStr(ParamCount + 5), ']');
  ArgStr(ParamCount + 5, s);
  WriteLn('oob_mgd=[', s, '] len=', Length(s));
  ArgStr(-1, s);
  WriteLn('neg_mgd=[', s, '] len=', Length(s));

  { The last argument is 300 x's — longer than LOCAL_STR_CAP, and sized from
    args_sizes_get rather than from any buffer this backend picked. A managed
    destination has no capacity to exceed, so it must come back whole. }
  ArgStr(ParamCount, s);
  n := 0;
  for i := 1 to Length(s) do
    if s[i] = 'x' then n := n + 1;
  WriteLn('long_len=', Length(s), ' xs=', n);

  { A loop counter next to the destination is exactly what the x86-64 bug
    overwrites, so read the long argument repeatedly and check the counter
    survives. On a smashed frame this never terminates. }
  n := 0;
  for i := 1 to 50 do
  begin
    ArgStr(ParamCount, s);
    n := n + 1;
  end;
  WriteLn('loop=', n);
  WriteLn('done');
end.
