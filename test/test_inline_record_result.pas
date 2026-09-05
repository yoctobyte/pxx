{$mode objfpc}
program test_inline_record_result;

{ Record-returning leaves inline at -O3 and MUST NOT change a value.

  Wired at -O0 AND -O3 because records are not admitted below -O3, so an
  -O2-only arm cannot catch anything here. optfuzz cannot catch it either, at
  all: pasmith returns only integer kinds from every function it generates, so
  no random program it produces has a record return in it
  (bug-t-pasmith-generates-no-float-code-so-optfuzz-cannot-see-float-optimizations).
  This directed matrix IS the coverage for the record admission axis.

  It has already earned that: the first working version of this feature
  SEGFAULTED at -O3 while -O0/-O2 were correct, because the splice returned
  IR_LOAD_SYM of a record symbol where an aggregate call yields IR_LEA of its
  hidden destination -- sixteen bytes of record handed to a caller expecting a
  pointer.

  Rows 6-8 must NOT inline and are here as the positive control, so a future
  guard cannot pass by declining everything: Narrow calls Trunc, CopyDd assigns
  the whole record rather than field-by-field, and PickDd branches.
  feature-opt-inline-float-and-record-returning-leaves }

type
  TDd  = record Hi, Lo: Double; end;
  TII  = record A, B: Integer; end;
  TMix = record I: Integer; D: Double; end;
  TOne = record V: Double; end;

function Fast2Sum(a, b: Double): TDd;
begin Result.Hi := a + b; Result.Lo := b - (Result.Hi - a); end;

function TwoSum(a, b: Double): TDd;
var bb: Double;
begin
  Result.Hi := a + b; bb := Result.Hi - a;
  Result.Lo := (a - (Result.Hi - bb)) + (b - bb);
end;

function MkII(a, b: Integer): TII;    begin Result.A := a; Result.B := b; end;
function MkMix(i: Integer; d: Double): TMix; begin Result.I := i; Result.D := d; end;
function MkOne(v: Double): TOne;      begin Result.V := v * 2.0; end;
function Narrow(a: Double): TII;      begin Result.A := Trunc(a); Result.B := 0; end;
function CopyDd(s: TDd): TDd;         begin Result := s; end;
{ Assigns Hi only: the record is not fully definite, so retention must DECLINE.
  If it did not, the caller's temp would keep stack garbage in Lo while Hi read
  perfectly right -- the one failure in this feature that is silent. Only Hi is
  printed, so the row is deterministic. }
function HalfOnly(a: Double): TDd;
begin Result.Hi := a * 2.0; end;

function PickDd(a, b: Double): TDd;
begin
  if a < b then begin Result.Hi := a; Result.Lo := b; end
  else begin Result.Hi := b; Result.Lo := a; end;
end;

var d: TDd; ii: TII; mx: TMix; o: TOne;
begin
  d := Fast2Sum(1.0, 1.0e-20);  Writeln('Fast2Sum ', d.Hi:0:17, ' ', d.Lo:0:20);
  d := TwoSum(1.0, 1.0e-20);    Writeln('TwoSum   ', d.Hi:0:17, ' ', d.Lo:0:20);
  ii := MkII(3, 4);             Writeln('MkII     ', ii.A, ' ', ii.B);
  mx := MkMix(7, 0.5);          Writeln('MkMix    ', mx.I, ' ', mx.D:0:4);
  o := MkOne(1.25);             Writeln('MkOne    ', o.V:0:4);
  ii := Narrow(3.9);            Writeln('Narrow   ', ii.A, ' ', ii.B);
  d := CopyDd(d);               Writeln('CopyDd   ', d.Hi:0:17);
  d := PickDd(2.0, 1.0);        Writeln('PickDd   ', d.Hi:0:4, ' ', d.Lo:0:4);
  d := HalfOnly(1.5);           Writeln('HalfOnly ', d.Hi:0:4);
end.
