{ A VIRTUAL method taking a 64-bit value AND returning one. Every 32-bit
  backend's virtual-call path pushed one word per argument, so the high half of
  an Int64 argument was dropped and the callee read garbage for it. It stayed
  invisible unless the RESULT was also 64-bit -- an Integer result truncated the
  damage away on the way back -- which is why the bug needed BOTH halves before
  anything showed (bug-a-virtual-method-int64-in-and-out-32bit).

  It was silent on arm32/riscv32 (wrong number) and a segfault on i386, and it
  reached the RTL: TStream.GetPosition is `Result := Seek(0, soCurrent)` and
  Seek is virtual with exactly this signature, so TMemoryStream.Position was
  wrong on every 32-bit target.

  The four cases are the axes that were narrowed one at a time: neither a
  64-bit argument nor a 64-bit return is enough on its own, and a non-virtual
  call was always fine.

  The by-value SET case is the same omission found by looking for it: the
  virtual path had no ladder at all, so `CountSet([eA,eC,eD])` answered 1 on
  i386 and 0 on riscv32 where FPC says 3. arm32 was right by accident (it
  passes sets by address on both paths). Fixing it also needed riscv32's
  virtual path to grow the >8-word stack spill the direct path already had —
  Self plus a 32-byte set is nine words. }
program test_virtual_int64_param_and_result;
type
  TE = (eA, eB, eC, eD);
  TES = set of TE;
  TB = class
  public
    function NoArg: Int64; virtual;                    { 64-bit result only }
    function I64ArgIntRes(const x: Int64): Integer; virtual;
    function IntArgI64Res(x: Integer): Int64; virtual;
    function I64Both(const x: Int64): Int64; virtual;  { the broken one }
    function Static64(const x: Int64): Int64;          { same sig, not virtual }
    function CountSet(const s: TES): Integer; virtual; { by-value set = 8 words }
  end;
function TB.NoArg: Int64; begin NoArg := 7; end;
function TB.I64ArgIntRes(const x: Int64): Integer; begin I64ArgIntRes := Integer(x) + 1; end;
function TB.IntArgI64Res(x: Integer): Int64; begin IntArgI64Res := x + 1; end;
function TB.I64Both(const x: Int64): Int64; begin I64Both := x + 1; end;
function TB.Static64(const x: Int64): Int64; begin Static64 := x + 1; end;
function TB.CountSet(const s: TES): Integer;
var e: TE; n: Integer;
begin
  n := 0;
  for e := eA to eD do if e in s then Inc(n);
  CountSet := n;
end;
function Plain64(const x: Int64): Int64; begin Plain64 := x + 1; end;
var b: TB; a, c, d, e, f, g: Int64; h: Integer;
begin
  b := TB.Create;
  a := b.NoArg;
  c := b.I64ArgIntRes(5);
  d := b.IntArgI64Res(5);
  e := b.I64Both(5);
  f := b.Static64(5);
  g := Plain64(5);
  writeln(a, '|', c, '|', d, '|', e, '|', f, '|', g);
  { a value that actually uses the high word, so a dropped high half cannot
    coincidentally pass }
  e := b.I64Both(10000000000);
  writeln(e);
  h := b.CountSet([eA, eC, eD]);
  writeln('set=', h);
  if (a = 7) and (c = 6) and (d = 6) and (e = 10000000001) and (f = 6) and (g = 6)
     and (h = 3) then
    writeln('PASS')
  else
    writeln('FAIL');
end.
