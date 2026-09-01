{ DOES A FRESH DYNAMIC ARRAY GET RELEASED, on every backend and every call kind.

  The dyn-array twin of test_managed_str_ownership_leaks.pas, and separate from
  it for one reason: xtensa cannot return a dynamic array from a function at all
  ("target xtensa: only ordinal/float/pointer/string function results supported
  yet", symtab.inc), so this program has no xtensa row. Folding these arms into
  that file would have broken its xtensa row for a gap that has nothing to do
  with ownership.

  WHAT LEAKED. Thirteen inline guards across the seven backends asked "is the
  value a direct IR_CALL" and nothing else, so an array arriving from a function
  POINTER, a VIRTUAL method or an INTERFACE method was retained a second time,
  its refcount never reached zero, and nothing was ever freed. Measured on
  x86-64 before the fix, 2000 iterations each:

      indirect   allocs=1871 frees=0     live=1871   (direct call: 1871/1869/2)
      virtual    allocs=1871 frees=0     live=1871
      interface  allocs=1871 frees=0     live=1871

  The direct-call arm was already correct, which is what named the bug: the same
  expression leaked or did not purely by how the callee was reached
  (bug-a-an-indirect-call-returning-a-dynamic-array-leaks-every-allocation-on-every-backend).

  HOW THIS FAILS. Built -dPXX_ALLOC_CENSUS the runtime prints exact allocation
  counters, identical across targets for one program, so the make rows compare
  each target against the x86-64 build of the same source. That catches a
  backend that DIVERGES. It is blind by construction to a leak every backend
  SHARES -- and this bug was exactly that, x86-64 included -- so every row is
  paired with tools/assert_no_leak.sh, which is the absolute check. A
  differential alone would have compared two equally wrong numbers and passed.

  NOT covered here, deliberately: `array of AnsiString`. It leaked through an
  indirect call exactly like the arms below and is fixed by the same change
  (x86-64 allocs=3799 frees=0 -> 3799/3796), but i386, arm32 and riscv32 build
  it with 5411 allocations against x86-64's and aarch64's 3799 -- a PRE-EXISTING
  divergence, measured identical on the parent commit and unrelated to
  ownership, so it fails nothing and leaks nothing. Wiring it into the
  cross-target rows would pin that known-bad number as expected. It has its own
  ticket: bug-a-array-of-ansistring-allocates-42-percent-more-on-i386-arm32-and-riscv32.

  The DIRECT arm is here as the in-program control: it did not leak before the
  fix and must not start. If every arm below ever reads the same as it did on a
  broken compiler, that is the control failing, not the subject passing. }
program test_dynarray_ownership_leaks;
type
  TIntArr = array of Integer;
  TMkArr = function(n: Integer): TIntArr;
  TBase = class
    function Mk(n: Integer): TIntArr; virtual;
  end;
  TDer = class(TBase)
    function Mk(n: Integer): TIntArr; override;
  end;
  IMaker = interface
    function Mk(n: Integer): TIntArr;
  end;
  TMaker = class(TInterfacedObject, IMaker)
    function Mk(n: Integer): TIntArr;
  end;

var
  i, k: Integer;
  a: TIntArr;
  fp: TMkArr;
  o: TBase; m: IMaker;

function MakeArr(n: Integer): TIntArr;
begin
  SetLength(MakeArr, 4);
  MakeArr[0] := 1;
end;

function TBase.Mk(n: Integer): TIntArr;
begin SetLength(Mk, 4); Mk[0] := 1; end;

function TDer.Mk(n: Integer): TIntArr;
begin SetLength(Mk, 4); Mk[0] := 2; end;

function TMaker.Mk(n: Integer): TIntArr;
begin SetLength(Mk, 4); Mk[0] := 3; end;

begin
  { the DIRECT arm — the control: correct before the fix, must stay correct }
  k := 0;
  for i := 1 to 2000 do
  begin
    a := MakeArr(i);
    k := k + a[0];
  end;
  Writeln('direct k=', k);

  { the INDIRECT arm — a call through a procedural variable }
  fp := @MakeArr;
  k := 0;
  for i := 1 to 2000 do
  begin
    a := fp(i);
    k := k + a[0];
  end;
  Writeln('indirect k=', k);

  { the VIRTUAL arm — dispatched through the VMT }
  o := TDer.Create;
  k := 0;
  for i := 1 to 2000 do
  begin
    a := o.Mk(i);
    k := k + a[0];
  end;
  Writeln('virtual k=', k);

  { the INTERFACE arm — dispatched through the interface table }
  m := TMaker.Create;
  k := 0;
  for i := 1 to 2000 do
  begin
    a := m.Mk(i);
    k := k + a[0];
  end;
  Writeln('interface k=', k);

end.
