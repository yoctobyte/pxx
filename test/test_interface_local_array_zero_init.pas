{ A LOCAL array of interfaces was never zero-initialised, so the first
  assignment to an element ran the ARC release on STACK GARBAGE.

    procedure P;
    var i: Integer; keep: array[0..2] of IFoo;
    begin
      keep[i] := nil;      { releases the "old value" -- which is stack junk;
    end;                     _Release dispatches through a garbage IMT }

  Every managed-local pass keys on SymIsComInterface, which answers False for an
  ARRAY on purpose (the array's slot is not itself a reference), and the
  managed-RECORD-array arm does not claim it either, because an interface UCls
  has no managed FIELDS. So `array[0..N] of IFoo` fell between the two and got
  neither zero-init nor cleanup.

  WHAT MADE THIS HARD TO SEE: it presented as `uses sysutils` causing a
  segfault. The same program without that one line ran fine. sysutils has
  nothing to do with it -- its initialisation merely DIRTIES the stack the
  routine is about to use. On a clean stack the garbage is zero and the bug is
  invisible, which is also why a constant index and a global array appeared to
  "work". So this test does not use sysutils: it dirties the stack ITSELF, with
  a routine that leaves a recognisable pattern at the depth the next call will
  reuse. That makes the failure deterministic instead of a lottery.

  The pinned binary SEGFAULTS on this file rather than printing a failure.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-a-a-local-array-of-interfaces-is-not-zero-initialised }
program test_interface_local_array_zero_init;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Name: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    fN: string;
    constructor Create(const n: string);
    function Name: string;
  end;

var
  pass, fail: Integer;

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
function TFoo.Name: string; begin Result := fN; end;

procedure Chk(const what: string; ok: Boolean);
begin
  if ok then begin Inc(pass); writeln('ok   ', what); end
  else begin Inc(fail); writeln('FAIL ', what); end;
end;

{ Leave a non-zero pattern on the stack at the depth the routines below use.
  Without this the frame is already zero and the bug cannot be observed. }
procedure DirtyTheStack;
var junk: array[0..31] of NativeInt; k: Integer;
begin
  for k := 0 to 31 do junk[k] := NativeInt($5A5A5A5A00) + k;
  if junk[0] = 0 then writeln('unreachable');
end;

{ 1. the minimal shape: assigning nil to a variable-indexed element }
function NilStore: Boolean;
var i: Integer; keep: array[0..2] of IFoo;
begin
  for i := 0 to 2 do keep[i] := nil;
  Result := keep[0] = nil;
end;

{ 2. filling the array with real objects and reading them back }
function FillAndRead: Boolean;
var i: Integer; keep: array[0..3] of IFoo; s: string;
begin
  for i := 0 to 3 do keep[i] := TFoo.Create('e');
  s := '';
  for i := 0 to 3 do s := s + keep[i].Name;
  for i := 0 to 3 do keep[i] := nil;
  Result := s = 'eeee';
end;

{ 3. overwriting an element -- the old occupant must be released, not leaked,
     and the release must not touch garbage }
function Overwrite: Boolean;
var i: Integer; keep: array[0..1] of IFoo;
begin
  for i := 0 to 1 do keep[i] := TFoo.Create('a');
  for i := 0 to 1 do keep[i] := TFoo.Create('b');
  Result := (keep[0].Name = 'b') and (keep[1].Name = 'b');
  for i := 0 to 1 do keep[i] := nil;
end;

{ 4. a constant index -- this one accidentally worked before, keep it honest }
function ConstIndex: Boolean;
var keep: array[0..2] of IFoo;
begin
  keep[0] := nil;
  keep[1] := TFoo.Create('c');
  Result := (keep[0] = nil) and (keep[1].Name = 'c');
  keep[1] := nil;
end;

{ 5. a two-dimensional local array of interfaces }
function TwoDim: Boolean;
var r, c: Integer; grid: array[0..1, 0..1] of IFoo;
begin
  for r := 0 to 1 do
    for c := 0 to 1 do grid[r][c] := TFoo.Create('g');
  Result := grid[1][1].Name = 'g';
  for r := 0 to 1 do
    for c := 0 to 1 do grid[r][c] := nil;
end;

begin
  pass := 0; fail := 0;

  DirtyTheStack; Chk('nil store into a variable-indexed element', NilStore);
  DirtyTheStack; Chk('fill with objects and read back', FillAndRead);
  DirtyTheStack; Chk('overwrite releases the old occupant', Overwrite);
  DirtyTheStack; Chk('constant index', ConstIndex);
  DirtyTheStack; Chk('two-dimensional array', TwoDim);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
