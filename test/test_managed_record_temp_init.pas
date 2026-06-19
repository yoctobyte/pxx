{ A hidden aggregate-result temp (for a nested record-returning call) is created
  during IR lowering, after the parser's prologue zero-init pass. If it holds a
  managed (dynarray) field and the call sits on an untaken branch (here the
  `MulS := Mk(0); Exit` early-exit, never reached for these inputs), the temp is
  never filled — yet the proc's scope-exit cleanup would release its managed
  field and free stack garbage, corrupting the FIRST call only. Codegen must
  nil-init the full extent of such temps. Closes
  bug-proc-local-managed-record-uninit. (x86-64 + arm32; i386/aarch64 also need
  the separate managed-record function-return fix.) }
program test_managed_record_temp_init;

type
  TR = record neg: Boolean; limbs: array of Int64; end;

function Mk(v: Int64): TR;
var r: TR;
begin
  r.neg := False; SetLength(r.limbs, 1); r.limbs[0] := v; Mk := r;
end;

function MulS(const a: TR; m: Int64): TR;
var r: TR;
begin
  if m = 0 then begin MulS := Mk(0); Exit; end;   { untaken early-exit w/ nested call }
  SetLength(r.limbs, 1); r.limbs[0] := a.limbs[0] * m; MulS := r;
end;

procedure Fact(n: Integer);
var acc: TR; i: Integer;
begin
  acc := Mk(1);
  for i := 2 to n do acc := MulS(acc, i);
  Writeln(n, '! = ', acc.limbs[0]);
end;

begin
  Fact(5);    { first call must be 120, not 240 }
  Fact(5);
  Fact(6);
end.
