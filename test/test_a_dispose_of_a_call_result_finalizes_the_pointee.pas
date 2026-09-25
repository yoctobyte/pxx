{$mode objfpc}{$H+}
program test_a_dispose_of_a_call_result_finalizes_the_pointee;
{ Dispose(F()) -- the pointer is a CALL RESULT -- finalizes F()^ and calls F
  exactly ONCE.

  Dispose(p) finalizes p^ by reading p three times (nil test, finalize, free),
  so it did so only for a pointer it could re-read with no effect. For a call it
  kept FreeMem alone and the managed pointee leaked: 33-160 B per Dispose on
  every target (the one open leak of the pre-release sweep). The call is now
  evaluated once into a hidden temp of the result's own pointer type.

  Each row prints the heap growth per iteration (must be 0) and how many times
  its routine ran per Dispose (must be 1: a lowering that re-evaluates the call
  would free one block and leak two). The CONTROL leaks 64 B/iter on purpose
  and must read at least 64, or this reading cannot see a leak at all. The nil
  row disposes a nil result, which must stay harmless.

  The last line is the same defect in `.Free`: `Objs[Pick(i)].Free` counted as
  re-readable, so Pick ran FOUR times per Free (pin v440). It must run once. }

type
  TA = array of Integer;
  IThing = interface ['{7A1E2D3C-1A2B-4C5D-8E9F-0A1B2C3D4E60}'] function N: Integer; end;
  TThing = class(TInterfacedObject, IThing) function N: Integer; end;
  TR = record s: AnsiString; n: Integer; end;
  TRR = record inner: TR; a: TA; v: Variant; end;
  TSA = array[0..3] of AnsiString;
  TPStr = ^AnsiString; TPDyn = ^TA; TPIntf = ^IThing; TPVar = ^Variant;
  TPRec = ^TR; TPRRec = ^TRR; TPInt = ^Integer; TPSA = ^TSA;
  TMaker = class function Make(i: Integer): TPRec; end;
  TObj = class end;

var Calls: Integer;
    Slots: array[0..2] of TPRec;
    Objs: array[0..2] of TObj;

function TThing.N: Integer; begin Result := 1; end;
function Str(k: Integer): AnsiString; begin Result := Copy('abcdefghijklmnopq', 1, 2 + k mod 13); end;
procedure Grow(var a: TA; n: Integer); begin SetLength(a, n); end;

function MkRec(i: Integer): TPRec; begin Inc(Calls); New(Result); Result^.s := Str(i); Result^.n := i; end;
function MkStr(i: Integer): TPStr; begin Inc(Calls); New(Result); Result^ := Str(i); end;
function MkDyn(i: Integer): TPDyn; begin Inc(Calls); New(Result); Grow(Result^, 10 + i mod 3); end;
function MkIntf(i: Integer): TPIntf; begin Inc(Calls); New(Result); Result^ := TThing.Create; end;
function MkVar(i: Integer): TPVar; begin Inc(Calls); New(Result); Result^ := Str(i); end;
function MkNest(i: Integer): TPRRec;
begin
  Inc(Calls); New(Result); Result^.inner.s := Str(i); Grow(Result^.a, 5); Result^.v := Str(i + 1);
end;
function MkArr(i: Integer): TPSA; var k: Integer;
begin Inc(Calls); New(Result); for k := 0 to 3 do Result^[k] := Str(i + k); end;
function MkInt(i: Integer): TPInt; begin Inc(Calls); New(Result); Result^ := i; end;
function MkNil(i: Integer): TPRec; begin Inc(Calls); Result := nil; end;
function TMaker.Make(i: Integer): TPRec; begin Result := MkRec(i); end;
function Pick(i: Integer): Integer; begin Inc(Calls); Result := i mod 3; end;
function Slot(i: Integer): Integer; begin Inc(Calls); Slots[i mod 3]^.s := Str(i); Result := i mod 3; end;

procedure Shape(k, i: Integer; m: TMaker);
begin
  case k of
    0: Dispose(MkRec(i));
    1: Dispose(MkStr(i));
    2: Dispose(MkDyn(i));
    3: Dispose(MkIntf(i));
    4: Dispose(MkVar(i));
    5: Dispose(MkNest(i));
    6: Dispose(MkArr(i));
    7: Dispose(m.Make(i));
    8: begin New(Slots[i mod 3]); Dispose(Slots[Slot(i)]); end;
    9: Dispose(MkInt(i));
    10: Dispose(MkNil(i));
  end;
end;

const
  N = 400;
  Names: array[0..10] of AnsiString = ('record', 'string', 'dynarray', 'interface',
    'variant', 'nested', 'fixed-array', 'method', 'element-by-call', 'unmanaged', 'nil');
var k, i: Integer; h0, d: Int64; p: Pointer; m: TMaker;
begin
  m := TMaker.Create;
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  for i := 1 to N do GetMem(p, 64);
  d := (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div N;
  WriteLn('control sees a leak: ', d >= 64);
  for k := 0 to 10 do
  begin
    for i := 1 to 20 do Shape(k, i, m);
    Calls := 0;
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    for i := 1 to N do Shape(k, i, m);
    d := (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div N;
    WriteLn(Names[k], ' bytes/iter=', d, ' calls/dispose=', Calls / N:0:2);
  end;
  Calls := 0;
  for i := 1 to N do begin Objs[i mod 3] := TObj.Create; Objs[Pick(i)].Free; end;
  WriteLn('free-element-by-call calls/free=', Calls / N:0:2);
  m.Free;
end.
