program AsmRv32;
{ Inline asm on riscv32 (feature-inline-asm-multi-arch): locals/params via
  s0-relative substitution, labels + branches, global access via la/@glob.
  Expected output: 42 / 55 / 42. }
var
  g: Integer;

function AddViaAsm(a, b: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    lw t0, a
    lw t1, b
    add t2, t0, t1
    sw t2, r
  end;
  Result := r;
end;

function SumLoop(n: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    lw t0, n
    addi t1, zero, 0
  loop:
    beq t0, zero, done
    add t1, t1, t0
    addi t0, t0, -1
    j loop
  done:
    sw t1, r
  end;
  Result := r;
end;

procedure BumpGlobal;
begin
  asm
    la t0, g
    lw t1, 0(t0)
    addi t1, t1, 5
    sw t1, 0(t0)
  end;
end;

begin
  writeln(AddViaAsm(19, 23));
  writeln(SumLoop(10));
  g := 37;
  BumpGlobal;
  writeln(g);
end.
