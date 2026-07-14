program test_esp_frozen_string;
{ Frozen inline strings (string[N] / shortstring) on the bare ESP targets
  (bug-frozen-string-unsupported-riscv32-xtensa). Exercises the pieces the
  riscv32 (b345) and xtensa (b354) ports added: the frozen IR_STORE_SYM arm
  (literal / char / managed / frozen sources), the frozen Length (buffer
  prefix, not heap header), and frozen -> managed materialisation at a call
  argument (PutS takes `const AnsiString`). The x86-64 oracle runs the same
  source over write(2); UART bytes must match byte-for-byte. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
end;

type
  TF = string[31];

var
  f, g: TF;
  m: AnsiString;
  c: Char;

begin
  f := 'hello';                 { literal -> frozen store }
  PutS('len='); PutInt(Length(f)); PutC(10);
  PutS(f); PutC(10);            { frozen -> managed param materialisation }

  c := 'X';
  f := c;                       { char -> frozen store }
  PutS('chr len='); PutInt(Length(f)); PutS(' v='); PutS(f); PutC(10);

  m := 'managed';
  f := m;                       { managed handle -> frozen store }
  PutS('from-m len='); PutInt(Length(f)); PutS(' v='); PutS(f); PutC(10);

  g := f;                       { frozen -> frozen store }
  PutS('copy len='); PutInt(Length(g)); PutS(' v='); PutS(g); PutC(10);

  m := f;                       { frozen -> managed assignment }
  PutS('back len='); PutInt(Length(m)); PutS(' v='); PutS(m); PutC(10);

{$ifdef PXX_ESP} while True do ; {$endif}
end.
