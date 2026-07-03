program AsmA64;
{ Inline asm on aarch64 (feature-inline-asm-multi-arch): locals/params via
  [x29,off] substitution, labels + branches (b.cond, cbz, b), global access
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
    ldr w9, a
    ldr w10, b
    add w11, w9, w10
    str w11, r
  end;
  Result := r;
end;

function SumLoop(n: Integer): Integer;
var r: Integer;
begin
  r := 0;
  asm
    ldr w9, n
    mov w10, 0
  loop:
    cbz w9, done
    add w10, w10, w9
    sub w9, w9, 1
    b loop
  done:
    str w10, r
  end;
  Result := r;
end;

procedure BumpGlobal;
begin
  asm
    ldr x9, g
    ldr w10, [x9]
    add w10, w10, 5
    str w10, [x9]
  end;
end;

begin
  writeln(AddViaAsm(19, 23));
  writeln(SumLoop(10));
  g := 37;
  BumpGlobal;
  writeln(g);
end.
