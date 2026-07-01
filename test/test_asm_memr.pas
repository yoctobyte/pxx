program AsmMemR;
{ Inline asm explicit memory operands (feature-inline-asm-depth TODO #3):
  [reg], [reg+disp], [reg+reg*scale], [reg+reg*scale+disp]. Wired through
  lib/asmcore's SIB-capable EmitModRMMem (exported from asmcore_x64 for
  exactly this) instead of re-deriving SIB encoding a second time in the
  compiler -- "library work first, dial it into the compiler." }
var
  arr: array[0..9] of longint;
  i: longint;
  total: longint;
  p: ^longint;

begin
  for i := 0 to 9 do arr[i] := i * 10;
  p := @arr[0];

  { [reg] bare }
  asm
    mov rbx, p
    mov eax, [rbx]
    mov total, eax
  end;
  writeln(total);   { arr[0] = 0 }

  { [reg+disp] }
  asm
    mov rbx, p
    mov eax, [rbx+8]
    mov total, eax
  end;
  writeln(total);   { arr[2] = 20 }

  { [reg+reg*scale] }
  asm
    mov rbx, p
    mov rcx, 3
    mov eax, [rbx+rcx*4]
    mov total, eax
  end;
  writeln(total);   { arr[3] = 30 }

  { [reg+reg*scale+disp] }
  asm
    mov rbx, p
    mov rcx, 2
    mov eax, [rbx+rcx*4+8]
    mov total, eax
  end;
  writeln(total);   { arr[4] = 40 }

  { store through [reg+reg*scale] (size from the reg operand) }
  asm
    mov rbx, p
    mov rcx, 5
    mov eax, 999
    mov [rbx+rcx*4], eax
  end;
  writeln(arr[5]);  { 999 }

  { unary on bare memory -- no reg in the instruction to disambiguate size,
    falls back to the documented dword default }
  asm
    mov rbx, p
    inc [rbx]
  end;
  writeln(arr[0]);  { 1 }

  { ALU mem,reg }
  asm
    mov rbx, p
    mov eax, 100
    add [rbx+4], eax
  end;
  writeln(arr[1]);  { 110 }

  { push/pop through an explicit memory operand (bypasses the typed
    x64_push_mem/x64_pop_mem helpers, which hardcode an [rbp+disp] base) }
  asm
    mov rbx, p
    push [rbx]
    pop rax
    mov total, eax
  end;
  writeln(total);   { arr[0] = 1 }
end.
