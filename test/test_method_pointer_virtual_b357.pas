program TestMethodPointerVirtual;
{$mode objfpc}{$H+}
{ Regression: `@baseref.VirtualMethod` must capture the DERIVED override through
  the object's VMT at runtime, not the static base-method address. The method-ref
  lowering emitted IR_PROCADDR of the static proc for every method, so a method
  pointer to a virtual method via a base-typed ref silently called the base method
  (bug-a-method-pointer-virtual-captures-static-address). Non-virtual method
  pointers must keep the static address. }
type
  TB = class
    function Stat(a: longint): longint;            { non-virtual }
    function Virt(a: longint): longint; virtual;
  end;
  TD = class(TB)
    function Virt(a: longint): longint; override;
  end;
  TFn = function(a: longint): longint of object;

function TB.Stat(a: longint): longint; begin Result := a + 10; end;
function TB.Virt(a: longint): longint; begin Result := a + 1; end;
function TD.Virt(a: longint): longint; begin Result := a + 1000; end;

var
  b: TB;
  fn: TFn;
begin
  b := TB.Create;
  fn := @b.Stat;  WriteLn('nonvirt=', fn(5));       { 15  }
  fn := @b.Virt;  WriteLn('virt-base=', fn(5));     { 6   }
  b.Free;

  b := TD.Create;                                   { base ref, derived instance }
  fn := @b.Virt;  WriteLn('virt-deriv=', fn(5));    { 1005 via VMT }
  WriteLn('direct=', b.Virt(5));                    { 1005 }
  b.Free;
end.
