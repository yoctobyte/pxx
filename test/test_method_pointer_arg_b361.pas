program TestMethodPointerArg;
{$mode objfpc}{$H+}
{ Regression: `@obj.Method` passed directly as an ARGUMENT to a named method-pointer
  (`of object`) parameter. Overload matching reported the AN_METHODREF as tyPointer
  and rejected it against the tyRecord method-pointer param ("no overload matches"),
  and the by-ref-argument check then rejected the non-lvalue methodref. The
  assignment form (`fn := @obj.M`) already worked; this makes the argument form work
  too, and it must respect virtual dispatch through a base ref
  (bug-pascal-methodref-arg-to-named-of-object-param-no-match). }
type
  TB = class
    function Stat(a: longint): longint;
    function Virt(a: longint): longint; virtual;
  end;
  TD = class(TB)
    function Virt(a: longint): longint; override;
  end;
  TFn = function(a: longint): longint of object;

function TB.Stat(a: longint): longint; begin Result := a + 10; end;
function TB.Virt(a: longint): longint; begin Result := a + 1; end;
function TD.Virt(a: longint): longint; begin Result := a + 1000; end;

procedure Call(fn: TFn);
begin
  WriteLn('cb=', fn(5));
end;

var
  b: TB;
begin
  b := TB.Create;
  Call(@b.Stat);           { cb=15  (non-virtual)   }
  Call(@b.Virt);           { cb=6   (virtual, base) }
  b.Free;

  b := TD.Create;
  Call(@b.Virt);           { cb=1005 (virtual override via base ref) }
  b.Free;
end.
