{ SPDX-License-Identifier: Zlib }
unit rtti;
{ Runtime reflection over the published-method table the compiler already emits.

  EmitRTTI writes, for every class with at least one published member, a blob whose
  layout is fixed by the RTTI_* constants in defs.inc:

    +0  name (char*)        +32 propCount        +64 fieldCount
    +8  parent RTTI         +40 props            +72 fields
    +16 instance size       +48 methCount
    +24 VMT                 +56 meths

  A method entry is 16 bytes: {name (char*), code (Pointer)}.

  An instance reaches its own blob through the BACKLINK the compiler reserves one
  word before the VMT: [instance+0] is the VMT address, so the blob is at
  [[instance+0] - 8]. Each blob lists only the class's OWN published methods; walk
  `parent` to see inherited ones.

  This is the surface a test framework discovers `Test*` methods with — the thing
  the self-host gate never exercises. See feature-rtti-method-reflection. }

interface

uses sysutils;

type
  { A parameterless published method, as a callable method pointer. This is the
    shape a test runner invokes a discovered `Test*` method through. }
  TRttiProc = procedure of object;

  { A discovered method, ready to call: the code address plus the instance it was
    discovered on. Same shape as a Pascal method pointer. }
  TRttiMethod = record
    Name: string;
    Code: Pointer;
    Instance: TObject;
  end;

{ The class RTTI blob of an instance, or nil if its class publishes nothing. }
function GetClassRtti(Instance: TObject): Pointer;
function GetRttiClassName(Rtti: Pointer): string;

{ Published methods, INCLUDING those inherited from ancestors. }
function PublishedMethodCount(Instance: TObject): Integer;
function PublishedMethodName(Instance: TObject; Index: Integer): string;
function PublishedMethodAddress(Instance: TObject; Index: Integer): Pointer;

{ Look a published method up by name (case-insensitive, like FPC). nil if absent. }
function FindPublishedMethod(Instance: TObject; const Name: string): Pointer;

{ Everything at once — what a test runner actually wants. }
function GetPublishedMethod(Instance: TObject; Index: Integer): TRttiMethod;

{ Bind a discovered method into a CALLABLE method pointer. This is the payoff: it
  closes the loop from "a name in the RTTI blob" to "run it". Returns an unassigned
  method pointer (Code = nil) when the name is not published — test with Assigned. }
function BindPublishedMethod(Instance: TObject; const Name: string): TRttiProc;
function BindPublishedMethodByIndex(Instance: TObject; Index: Integer): TRttiProc;

implementation

type
  PPointer_ = ^Pointer;
  PNativeInt_ = ^NativeInt;

const
  RTTI_OFS_NAME       = 0;
  RTTI_OFS_PARENT     = 8;
  RTTI_OFS_METHCOUNT  = 48;
  RTTI_OFS_METHS      = 56;
  RTTI_METH_ENTRY     = 16;   { {name, code} }
  RTTI_METH_OFS_NAME  = 0;
  RTTI_METH_OFS_CODE  = 8;

function PtrAt(Base: Pointer; Ofs: Integer): Pointer;
begin
  PtrAt := PPointer_(PtrUInt(Base) + PtrUInt(Ofs))^;
end;

function IntAt(Base: Pointer; Ofs: Integer): NativeInt;
begin
  IntAt := PNativeInt_(PtrUInt(Base) + PtrUInt(Ofs))^;
end;

function CStrToStr(P: Pointer): string;
{ Blob names are INTERNED FROZEN STRINGS, not bare char*: the pointer targets an
  8-byte length prefix and the chars start at +8 (with a NUL after them, so +8 is
  also a valid C string). Read the length rather than scanning for the NUL. }
var pc: ^Char; s: string; n, i: NativeInt;
begin
  s := '';
  if P <> nil then
  begin
    n := PNativeInt_(P)^;
    if (n > 0) and (n < 1024) then
    begin
      pc := Pointer(PtrUInt(P) + 8);
      i := 0;
      while i < n do
      begin
        s := s + pc^;
        pc := Pointer(PtrUInt(pc) + 1);
        i := i + 1;
      end;
    end;
  end;
  CStrToStr := s;
end;

function GetClassRtti(Instance: TObject): Pointer;
var vmt: Pointer;
begin
  GetClassRtti := nil;
  if Instance = nil then Exit;
  vmt := PPointer_(Instance)^;                  { [instance+0] = VMT address }
  if vmt = nil then Exit;
  GetClassRtti := PPointer_(PtrUInt(vmt) - 8)^; { the backlink sits before the VMT }
end;

function GetRttiClassName(Rtti: Pointer): string;
begin
  if Rtti = nil then GetRttiClassName := ''
  else GetRttiClassName := CStrToStr(PtrAt(Rtti, RTTI_OFS_NAME));
end;

function RttiMethodCount(Rtti: Pointer): Integer;
{ own + inherited, walking the parent chain }
var n: Integer; cur: Pointer;
begin
  n := 0;
  cur := Rtti;
  while cur <> nil do
  begin
    n := n + Integer(IntAt(cur, RTTI_OFS_METHCOUNT));
    cur := PtrAt(cur, RTTI_OFS_PARENT);
  end;
  RttiMethodCount := n;
end;

function RttiMethodEntry(Rtti: Pointer; Index: Integer): Pointer;
{ The Index'th method across the chain, own-first then up through the ancestors.
  nil when Index is out of range. }
var cur, meths: Pointer; cnt, i: Integer;
begin
  RttiMethodEntry := nil;
  if Index < 0 then Exit;
  i := Index;
  cur := Rtti;
  while cur <> nil do
  begin
    cnt := Integer(IntAt(cur, RTTI_OFS_METHCOUNT));
    if i < cnt then
    begin
      meths := PtrAt(cur, RTTI_OFS_METHS);
      if meths = nil then Exit;
      RttiMethodEntry := Pointer(PtrUInt(meths) + PtrUInt(i * RTTI_METH_ENTRY));
      Exit;
    end;
    i := i - cnt;
    cur := PtrAt(cur, RTTI_OFS_PARENT);
  end;
end;

function PublishedMethodCount(Instance: TObject): Integer;
begin
  PublishedMethodCount := RttiMethodCount(GetClassRtti(Instance));
end;

function PublishedMethodName(Instance: TObject; Index: Integer): string;
var e: Pointer;
begin
  e := RttiMethodEntry(GetClassRtti(Instance), Index);
  if e = nil then PublishedMethodName := ''
  else PublishedMethodName := CStrToStr(PtrAt(e, RTTI_METH_OFS_NAME));
end;

function PublishedMethodAddress(Instance: TObject; Index: Integer): Pointer;
var e: Pointer;
begin
  e := RttiMethodEntry(GetClassRtti(Instance), Index);
  if e = nil then PublishedMethodAddress := nil
  else PublishedMethodAddress := PtrAt(e, RTTI_METH_OFS_CODE);
end;

function FindPublishedMethod(Instance: TObject; const Name: string): Pointer;
var i, n: Integer;
begin
  FindPublishedMethod := nil;
  n := PublishedMethodCount(Instance);
  for i := 0 to n - 1 do
    if CompareText(PublishedMethodName(Instance, i), Name) = 0 then
    begin
      FindPublishedMethod := PublishedMethodAddress(Instance, i);
      Exit;
    end;
end;

function GetPublishedMethod(Instance: TObject; Index: Integer): TRttiMethod;
var m: TRttiMethod;
begin
  m.Name := PublishedMethodName(Instance, Index);
  m.Code := PublishedMethodAddress(Instance, Index);
  m.Instance := Instance;
  GetPublishedMethod := m;
end;

function BindMethodPtr(Code: Pointer; Instance: TObject): TRttiProc;
{ A method pointer is the 16-byte pair {Code, Data} (Code at +0, the instance at
  +8) — the same layout the compiler stores for `@obj.Method`. Write the two words
  through the variable's address: casting a plain record to a method-pointer type
  does NOT produce a callable one. }
var m: TRttiProc; base: PtrUInt;
begin
  base := PtrUInt(@m);
  PPointer_(base)^ := Code;
  PPointer_(base + 8)^ := Pointer(Instance);
  BindMethodPtr := m;
end;

function BindPublishedMethodByIndex(Instance: TObject; Index: Integer): TRttiProc;
begin
  BindPublishedMethodByIndex :=
    BindMethodPtr(PublishedMethodAddress(Instance, Index), Instance);
end;

function BindPublishedMethod(Instance: TObject; const Name: string): TRttiProc;
begin
  BindPublishedMethod := BindMethodPtr(FindPublishedMethod(Instance, Name), Instance);
end;

end.
