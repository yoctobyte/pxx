program test_esp_bare_managed;
{ Managed RECORDS on the bare ESP profile — the shape test_esp_bare.pas and the
  thirteen rows beside it all avoid, which is exactly why nobody noticed they
  did not compile.

  Until 2026-09-20 every one of these refused on --esp-profile=bare with
  `compiler error: PXXRecordRelease not found` (and Retain / Initialize /
  Finalize for the other arms). Nothing was unimplementable: builtinheap.pas
  gated whole CONTIGUOUS SPANS of source on the profile marker, so the record
  and dynarray walks were excluded for sitting next to PXXStrLoadFile, which
  genuinely needs a filesystem. A suite that avoids the shape certifies its
  absence — so this file exists to contain the shape.
  feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent

  It asserts VALUES, not just that the build succeeds: the same source runs on
  x86-64 over write(2) and the serial bytes must match byte-for-byte, so a walk
  that compiles and then corrupts a refcount is a diff, not a pass. A
  compile-only row could not tell those apart.

  Same PutC/PutS scaffolding as test_esp_bare.pas: UART0 MMIO on bare, a raw
  write syscall on the oracle. }

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

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

type
  TInner = record s: AnsiString; end;
  TOuter = record i: TInner; tag: AnsiString; n: Integer; end;

{ A managed local going out of scope — PXXRecordRelease. This is the arm that
  refused, and it is the most ordinary Pascal in the file. }
procedure LocalScope;
var r: TOuter;
begin
  r.i.s := 'in';
  r.tag := 'local';
  r.n := 1;
  PutS(r.tag); PutC(58); PutS(r.i.s); PutC(10);
end;

{ Whole-record assignment — PXXRecordRetain on the source side. If the retain
  is missed the copy's strings are freed once too often; if it double-retains
  they leak. Reading BOTH after the copy is what makes either visible. }
procedure AssignCopy;
var a, b: TOuter;
begin
  a.i.s := 'src'; a.tag := 'copy'; a.n := 2;
  b := a;
  PutS(b.tag); PutC(58); PutS(b.i.s); PutC(58); PutS(a.i.s); PutC(10);
end;

{ Finalize + reuse — PXXRecordFinalize then PXXRecordZeroManaged. A Finalize
  that releases but does not zero turns the second assignment into a release of
  freed memory, so the reuse is the assertion, not decoration. }
procedure FinalizeReuse;
var r: TOuter;
begin
  r.i.s := 'one'; r.tag := 'fin'; r.n := 3;
  Finalize(r);
  r.i.s := 'two'; r.tag := 'fin2';
  PutS(r.tag); PutC(58); PutS(r.i.s); PutC(10);
end;

begin
  LocalScope;
  AssignCopy;
  FinalizeReuse;
  PutS('managed ok'); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.
