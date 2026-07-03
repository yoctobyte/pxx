program Asm386;
{ Inline asm on i386 (feature-inline-asm-multi-arch): locals/params via
  [ebp±off] substitution, labels + jcc branches, global access via
  mov/@glob (address load; dereference through the register).
  Expected output: 42 / 55 / 42. }
var
  g: Integer;

function AddViaAsm(a, b: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    mov eax, a
    mov ecx, b
    add eax, ecx
    mov r, eax
  end;
  Result := r;
end;

function SumLoop(n: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    mov ecx, n
    mov eax, 0
  loop_top:
    cmp ecx, 0
    je done
    add eax, ecx
    sub ecx, 1
    jmp loop_top
  done:
    mov r, eax
  end;
  Result := r;
end;

procedure BumpGlobal;
begin
  asm
    mov ecx, g
    mov eax, [ecx]
    add eax, 5
    mov [ecx], eax
  end;
end;

begin
  writeln(AddViaAsm(19, 23));
  writeln(SumLoop(10));
  g := 37;
  BumpGlobal;
  writeln(g);
end.
