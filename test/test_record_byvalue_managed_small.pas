program test_record_byvalue_managed_small;
{ Regression: a by-value record PARAMETER whose record has managed fields must
  be a private copy the callee owns — at ANY size. Records <= 8 bytes travel
  INLINE in the param slot (a raw byte copy of the caller's handles, retained by
  nobody), so a store into the parameter released the CALLER's handles: the
  caller's variable silently changed under it, then the freed block was reused
  and a later run tripped a write-after-free segfault.
  Filed as arm32-only because the trigger is pointer-width dependent — a record
  of Boolean + dynarray handle is 16 bytes on 64-bit (already by-ref, correct)
  but 8 on 32-bit. It reproduces on x86-64 too with a record that is <= 8 bytes
  there, which is what this test uses.
  bug-a-arm32-write-after-free-kills-four-lib-tests. }
type
  TOneField = record limbs: array of Int64; end;      { 8 bytes on 64-bit }
  TWithBool = record neg: Boolean; limbs: array of Int64; end;  { 8 on 32-bit }

function Make(v: Int64): TOneField;
begin
  SetLength(Result.limbs, 2);
  Result.limbs[0] := v; Result.limbs[1] := v * 2;
end;

function MakeB(v: Int64): TWithBool;
begin
  SetLength(Result.limbs, 2);
  Result.limbs[0] := v; Result.limbs[1] := v * 2;
end;

{ mutates its by-value parameter — must not touch the caller's record }
function Mutate(a: TOneField; n: Integer): Int64;
var q: TOneField; i: Integer;
begin
  for i := 1 to n do begin q := Make(100 + i); a := q; end;
  Mutate := a.limbs[0];
end;

function MutateB(a: TWithBool; n: Integer): Int64;
var q: TWithBool; i: Integer;
begin
  for i := 1 to n do begin q := MakeB(200 + i); a := q; end;
  MutateB := a.limbs[0];
end;

{ read-only use of the same parameter shape }
function ReadOnly(a: TOneField): Integer;
begin
  ReadOnly := Length(a.limbs);
end;

var u: TOneField; v: TWithBool; k: Integer;
begin
  u := Make(7);
  v := MakeB(9);
  for k := 1 to 3 do
  begin
    writeln(Mutate(u, 4), ' ', u.limbs[0], ' ', u.limbs[1]);
    writeln(MutateB(v, 4), ' ', v.limbs[0], ' ', v.limbs[1]);
    writeln(ReadOnly(u), ' ', u.limbs[0]);
  end;
  writeln('OK');
end.
