program AsmFunc;
{ assembler-modifier function: params read by name, result left in eax. }

function AddMul(a, b: longint): longint; assembler;
{$asmMode intel}
asm
  mov eax, a
  add eax, b
  add eax, eax    { (a+b)*2 }
end;

var
  r: longint;
begin
  r := AddMul(3, 4);
  writeln(r);       { expect 14 }
end.
