program test_esp_class;
{ Class instantiation + virtual dispatch on the bare ESP targets
  (feature-xtensa-class-instantiation): TShape.Create allocates from the
  static arena, stores the VMT, runs the ctor; a.Get dispatches through
  [Self] -> VMT -> slot. The x86-64 oracle runs the same source over a
  write(2) syscall, so the serial bytes must match byte-for-byte. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer);
begin
  esp_rom_printf('%c', code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}
{$endif}

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
  TShape = class
    FSide: Integer;
    constructor Create(s: Integer);
    function Get: Integer; virtual;
    function Peri(scale, extra: Integer): Integer; virtual;
  end;
  TSquare = class(TShape)
    function Get: Integer; override;
    function Peri(scale, extra: Integer): Integer; override;
  end;

constructor TShape.Create(s: Integer);
begin
  FSide := s;
end;

function TShape.Get: Integer;
begin
  Get := FSide;
end;

function TShape.Peri(scale, extra: Integer): Integer;
begin
  Peri := FSide * scale + extra;
end;

function TSquare.Get: Integer;
begin
  Get := FSide * FSide;
end;

function TSquare.Peri(scale, extra: Integer): Integer;
begin
  Peri := 4 * FSide * scale + extra;
end;

var
  a: TShape;
begin
  a := TShape.Create(7);
  PutInt(a.Get); PutC(10);          { 7 }
  PutInt(a.Peri(3, 1)); PutC(10);   { 22 }
  a := TSquare.Create(7);
  PutInt(a.Get); PutC(10);          { 49 }
  PutInt(a.Peri(2, 5)); PutC(10);   { 61 }
{$ifdef PXX_ESP} while True do ; {$endif}
end.
