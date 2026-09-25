{$mode objfpc}{$H+}
program test_a_dispose_finalizes_the_managed_pointee;
{ Dispose(p) FINALIZES p^ before it frees the block.

  It was FreeMem alone, so whatever managed value the block held was never
  released: `New(p); p^.s := s2; Dispose(p)` leaked the string on every target
  (33 B/iter here for x86-64, i386, aarch64, arm32, riscv32, xtensa both ABIs).
  fpc reads 0 on the same rows.

  Each row runs its shape N times after a warm-up and prints the heap growth per
  iteration; every row must read 0. The CONTROL leaks 64 B/iter on purpose
  (GetMem, never freed) and must read at least 64, or this reading cannot see a
  leak at all. The last row disposes a nil pointer to a managed record, which
  must stay harmless. }

type
  TA = array of Integer;
  IThing = interface ['{6F1E2D3C-1A2B-4C5D-8E9F-0A1B2C3D4E5F}'] function N: Integer; end;
  TThing = class(TInterfacedObject, IThing) function N: Integer; end;
  TR = record s: AnsiString; n: Integer; end;
  TRR = record inner: TR; a: TA; v: Variant; end;
  TPStr = ^AnsiString; TPDyn = ^TA; TPIntf = ^IThing; TPVar = ^Variant;
  TPRec = ^TR; TPRRec = ^TRR; TPInt = ^Integer;
  THolder = class fp: TPRec; end;

function TThing.N: Integer; begin Result := 1; end;
function Str(k: Integer): AnsiString; begin Result := Copy('abcdefghijklmnopq', 1, 2 + k mod 13); end;
procedure Grow(var a: TA; n: Integer); begin SetLength(a, n); end;

procedure Shape(k, i: Integer);
var ps: TPStr; pa: TPDyn; pi: TPIntf; pv: TPVar; pr: TPRec; prr: TPRRec;
    pn: TPInt; h: THolder; arr: array[0..2] of TPRec;
begin
  case k of
    0: begin New(pr); pr^.s := Str(i); pr^.n := i; Dispose(pr); end;
    1: begin New(ps); ps^ := Str(i); Dispose(ps); end;
    2: begin New(pa); Grow(pa^, 10); Dispose(pa); end;
    3: begin New(pi); pi^ := TThing.Create; Dispose(pi); end;
    4: begin New(pv); pv^ := Str(i); Dispose(pv); end;
    5: begin New(prr); prr^.inner.s := Str(i); Grow(prr^.a, 5); prr^.v := Str(i + 1); Dispose(prr); end;
    6: begin h := THolder.Create; New(h.fp); h.fp^.s := Str(i); Dispose(h.fp); h.Free; end;
    7: begin New(arr[1]); arr[1]^.s := Str(i); Dispose(arr[1]); end;
    8: begin New(pn); pn^ := i; Dispose(pn); end;
    9: begin pr := nil; Dispose(pr); end;
  end;
end;

const
  N = 400;
  Names: array[0..9] of AnsiString = ('record', 'string', 'dynarray', 'interface',
    'variant', 'nested', 'field-pointer', 'element-pointer', 'unmanaged', 'nil');
var k, i: Integer; h0, d: Int64; p: Pointer;
begin
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  for i := 1 to N do GetMem(p, 64);
  d := (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div N;
  WriteLn('control sees a leak: ', d >= 64);
  for k := 0 to 9 do
  begin
    for i := 1 to 20 do Shape(k, i);
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    for i := 1 to N do Shape(k, i);
    d := (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div N;
    WriteLn(Names[k], ' bytes/iter=', d);
  end;
end.
