program test_fpc_compat_batch2;
{ FPC-RTL compatibility batch 2 (fgl/TFPSList bring-up): method overloads,
  method pointers as params/args, unqualified setter-property writes,
  nested class-local types, TClass.AnyCtor construction, ReallocMem on a
  field, memory builtins (FillByte/CompareByte/CompareMem), dword/PtrUInt
  casts, `raise ... at`, and @BareMethod with implicit Self. }

uses sysutils;

type
  TCmp = function(a, b: Pointer): Integer of object;

  TL = class
  private
    type
      TPairFn = function(x: Integer): Integer;   { nested class-local type }
      PInt = ^Integer;
  private
    FCap: Integer;
    FBuf: Pointer;
    FOnCmp: TCmp;
    procedure SetCap(v: Integer);
  public
    hits: Integer;
    function Cmp7(a, b: Pointer): Integer;
    procedure Deref(p: Pointer); overload;          { fgl's overload pair shape }
    procedure Deref(a, b: Integer); overload;
    function UseCallback(c: TCmp): Integer;
    function NilDef(p: Pointer = nil): Boolean;
    function UseField: Integer;
    procedure GrowViaProp;
    procedure HookSelf;
    property Cap: Integer read FCap write SetCap;   { setter-method property }
  end;
  TD = class(TL)
    procedure Deref(a, b: Integer); overload;       { override-ish shadow }
    procedure CallInherited;
  end;

var
  total, okc: Integer;

procedure Check(name: string; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

procedure TL.SetCap(v: Integer);
begin
  FCap := v * 10;
end;

function TL.Cmp7(a, b: Pointer): Integer;
begin
  Cmp7 := 7;
end;

procedure TL.Deref(p: Pointer);
begin
  hits := hits + 1;
end;

procedure TL.Deref(a, b: Integer);
begin
  hits := hits + a + b;
end;

function TL.UseCallback(c: TCmp): Integer;
begin
  { indirect call through a method-pointer PARAM, in an expression }
  if c(nil, nil) > 0 then
    UseCallback := c(nil, nil)
  else
    UseCallback := -1;
end;

function TL.NilDef(p: Pointer): Boolean;
begin
  NilDef := p = nil;
end;

function TL.UseField: Integer;
begin
  { indirect call through a method-pointer FIELD, unqualified }
  UseField := FOnCmp(nil, nil);
end;

procedure TL.GrowViaProp;
begin
  Cap := 5;                      { unqualified setter-method property write }
  ReallocMem(FBuf, 32);          { ReallocMem on a FIELD lvalue }
  FillChar(FBuf^, 32, 65);
end;

procedure TL.HookSelf;
begin
  FOnCmp := @Cmp7;               { @BareMethod == @Self.Cmp7 }
end;

procedure TD.Deref(a, b: Integer);
begin
  hits := hits + 100;
end;

procedure TD.CallInherited;
begin
  inherited Deref(2, 3);         { overload-aware inherited }
end;

type
  EX = class(Exception)
  end;

var
  l: TL;
  d: TD;
  pb: PChar;
  p1, p2: array[0..7] of Byte;
  k: Integer;
  caught: AnsiString;
begin
  total := 0; okc := 0;

  l := TL.Create;
  l.hits := 0;
  l.Deref(nil);
  Check('overload-ptr-form', l.hits = 1);
  l.Deref(2, 3);
  Check('overload-int-form', l.hits = 6);

  Check('methodptr-param-arg-and-call', l.UseCallback(@l.Cmp7) = 7);
  l.HookSelf;
  Check('bare-at-method-and-field-call', l.UseField = 7);
  Check('nil-default-param', l.NilDef and not l.NilDef(@k));

  l.FBuf := nil;
  GetMem(l.FBuf, 8);
  l.GrowViaProp;
  Check('setter-prop-write', l.FCap = 50);
  pb := PChar(l.FBuf);
  Check('reallocmem-field', pb[31] = 'A');
  FreeMem(l.FBuf);
  l.Free;

  d := TD.Create;
  d.hits := 0;
  d.CallInherited;
  Check('inherited-overload', d.hits = 5);
  d.Free;

  FillByte(p1, 8, 3);
  FillByte(p2, 8, 3);
  Check('fillbyte-comparebyte-eq', CompareByte(p1, p2, 8) = 0);
  p2[5] := 9;
  Check('comparebyte-diff', CompareByte(p1, p2, 8) < 0);
  Check('comparemem', not CompareMem(@p1, @p2, 8));

  k := -1;
  Check('dword-cast', (dword(k) > 0) and (PtrUInt(@k) <> 0));

  caught := '';
  try
    raise EX.CreateFmt('boom %d', [42]);   { non-Create ctor + [..] arg + Format }
  except
    on e: EX do caught := e.Message;
  end;
  Check('createfmt-raise', caught = 'boom 42');

  writeln('total ok ', okc, ' / ', total);
end.
