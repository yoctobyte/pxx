program AsmArm32;
{ Inline asm on arm32 (feature-inline-asm-multi-arch): locals/params via
  [fp,off] substitution, labels + condition-suffixed branches, global access
  via ldr/@glob. Immediates are written WITHOUT '#' (the Pascal lexer would
  read #4 as a char literal); the engine accepts both forms.
  Expected output: 42 / 55 / 42. }
var
  g: Integer;

function AddViaAsm(a, b: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    ldr r0, a
    ldr r1, b
    add r2, r0, r1
    str r2, r
  end;
  Result := r;
end;

function SumLoop(n: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    ldr r0, n
    mov r1, 0
  loop:
    cmp r0, 0
    beq done
    add r1, r1, r0
    sub r0, r0, 1
    b loop
  done:
    str r1, r
  end;
  Result := r;
end;

procedure BumpGlobal;
begin
  asm
    ldr r0, g
    ldr r1, [r0]
    add r1, r1, 5
    str r1, [r0]
  end;
end;

begin
  writeln(AddViaAsm(19, 23));
  writeln(SumLoop(10));
  g := 37;
  BumpGlobal;
  writeln(g);
end.
