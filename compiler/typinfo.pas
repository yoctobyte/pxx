unit typinfo;

interface

type
  PString = ^string;

  TMethod = record
    Code: Pointer;
    Data: Pointer;
  end;
  PMethod = ^TMethod;

  TMethInfo = record
    NamePtr: PString;
    Code:    Pointer;
  end;
  PMethInfo = ^TMethInfo;

  TClassRTTI = record
    NamePtr:      PString;
    ParentRTTI:   Pointer; { actually PClassRTTI }
    InstanceSize: Int64;
    VMTPtr:       Pointer;
    PropCount:    Int64;
    PropsPtr:     Pointer; { actually PPropInfo }
    MethCount:    Int64;
    MethsPtr:     PMethInfo;
  end;
  PClassRTTI = ^TClassRTTI;

  TPropInfo = record
    NamePtr: PString;
    Kind:    Int64;      { 0=int, 1=string, 2=class, 3=enum, 4=set, 5=method }
    TypeRef: Pointer;    { pointer to EnumRTTI or ClassRTTI or nil }
    GetKind: Int64;      { 0=field, 1=method }
    GetRef:  Int64;      { field offset or method code ptr }
    SetKind: Int64;      { 0=field, 1=method }
    SetRef:  Int64;      { field offset or method code ptr }
    OrdType: Int64;      { type kind hint (size/sign for ordinals) }
  end;
  PPropInfo = ^TPropInfo;

  TRTTIEntry = record
    NamePtr: PString;
    RTTIPtr: PClassRTTI;
  end;
  PRTTIEntry = ^TRTTIEntry;

  TRegistry = record
    Count: Int64;
    Dummy: TRTTIEntry;
  end;
  PRegistry = ^TRegistry;

  TPropList = array[0..511] of PPropInfo;
  PPropList = ^TPropList;
  PPPropInfo = ^PPropInfo;

  PInt8   = ^ShortInt;
  PUInt8  = ^Byte;
  PInt16  = ^SmallInt;
  PUInt16 = ^Word;
  PInt32  = ^Integer;
  PInt64  = ^Int64;

function GetClass(const name: string): PClassRTTI;
function GetPropInfo(cls: PClassRTTI; const name: string): PPropInfo;
function GetPropList(cls: PClassRTTI; list: PPropList): Integer;
function GetOrdProp(instance: Pointer; p: PPropInfo): Int64;
procedure SetOrdProp(instance: Pointer; p: PPropInfo; v: Int64);
function GetStrProp(instance: Pointer; p: PPropInfo): string;
procedure SetStrProp(instance: Pointer; p: PPropInfo; const v: string);
function GetMethodProp(instance: Pointer; p: PPropInfo): TMethod;
procedure SetMethodProp(instance: Pointer; p: PPropInfo; const v: TMethod);
function GetMethodAddr(cls: PClassRTTI; const name: string): Pointer;

implementation

function TypeKindSize(tk: Int64): Integer;
begin
  if (tk = 2) or (tk = 3) or (tk = 7) or (tk = 8) then TypeKindSize := 1
  else if (tk = 9) or (tk = 10) then TypeKindSize := 2
  else if (tk = 1) or (tk = 11) or (tk = 12) then TypeKindSize := 4
  else TypeKindSize := 8;
end;

function TypeKindSigned(tk: Int64): Boolean;
begin
  if (tk = 7) or (tk = 9) or (tk = 1) or (tk = 11) or (tk = 13) or (tk = 15) then
    TypeKindSigned := True
  else
    TypeKindSigned := False;
end;

function GetClass(const name: string): PClassRTTI;
var
  reg: PRegistry;
  entries: PRTTIEntry;
  i: Integer;
begin
  GetClass := nil;
  reg := __rttireg();
  if reg = nil then Exit;
  entries := @reg^.Dummy;
  for i := 0 to Integer(reg^.Count) - 1 do
  begin
    if entries[i].NamePtr^ = name then
    begin
      GetClass := entries[i].RTTIPtr;
      Exit;
    end;
  end;
end;

function GetPropInfo(cls: PClassRTTI; const name: string): PPropInfo;
var
  curr: PClassRTTI;
  props: PPropInfo;
  i: Integer;
begin
  GetPropInfo := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.PropCount > 0 then
    begin
      props := PPropInfo(curr^.PropsPtr);
      for i := 0 to Integer(curr^.PropCount) - 1 do
      begin
        if props[i].NamePtr^ = name then
        begin
          GetPropInfo := @props[i];
          Exit;
        end;
      end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function GetPropList(cls: PClassRTTI; list: PPropList): Integer;
var
  curr: PClassRTTI;
  props: PPropInfo;
  plist: PPPropInfo;
  i, count: Integer;
begin
  count := 0;
  curr := cls;
  plist := PPPropInfo(list);
  while curr <> nil do
  begin
    if curr^.PropCount > 0 then
    begin
      props := PPropInfo(curr^.PropsPtr);
      for i := 0 to Integer(curr^.PropCount) - 1 do
      begin
        plist[count] := @props[i];
        Inc(count);
      end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
  GetPropList := count;
end;

function GetOrdProp(instance: Pointer; p: PPropInfo): Int64;
var
  addr: Pointer;
  sz, tk: Integer;
  sgn: Boolean;
begin
  GetOrdProp := 0;
  if p^.GetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.GetRef];
    tk := Integer(p^.OrdType);
    sz := TypeKindSize(tk);
    sgn := TypeKindSigned(tk);

    if sz = 1 then
    begin
      if sgn then GetOrdProp := PInt8(addr)^
      else GetOrdProp := PUInt8(addr)^;
    end
    else if sz = 2 then
    begin
      if sgn then GetOrdProp := PInt16(addr)^
      else GetOrdProp := PUInt16(addr)^;
    end
    else if sz = 4 then
    begin
      GetOrdProp := PInt32(addr)^;
    end
    else
    begin
      GetOrdProp := PInt64(addr)^;
    end;
  end;
end;

procedure SetOrdProp(instance: Pointer; p: PPropInfo; v: Int64);
var
  addr: Pointer;
  sz, tk: Integer;
begin
  if p^.SetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.SetRef];
    tk := Integer(p^.OrdType);
    sz := TypeKindSize(tk);

    if sz = 1 then
    begin
      PUInt8(addr)^ := Byte(v);
    end
    else if sz = 2 then
    begin
      PUInt16(addr)^ := Word(v);
    end
    else if sz = 4 then
    begin
      PInt32(addr)^ := Integer(v);
    end
    else
    begin
      PInt64(addr)^ := v;
    end;
  end;
end;

function GetStrProp(instance: Pointer; p: PPropInfo): string;
var
  addr: Pointer;
begin
  GetStrProp := '';
  if p^.GetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.GetRef];
    GetStrProp := PString(addr)^;
  end;
end;

procedure SetStrProp(instance: Pointer; p: PPropInfo; const v: string);
var
  addr: Pointer;
begin
  if p^.SetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.SetRef];
    PString(addr)^ := v;
  end;
end;

// Event Support

function GetMethodProp(instance: Pointer; p: PPropInfo): TMethod;
var
  addr: Pointer;
  m: TMethod;
begin
  m.Code := nil;
  m.Data := nil;
  if p^.GetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.GetRef];
    m := PMethod(addr)^;
  end;
  GetMethodProp := m;
end;

procedure SetMethodProp(instance: Pointer; p: PPropInfo; const v: TMethod);
var
  addr: Pointer;
begin
  if p^.SetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.SetRef];
    PMethod(addr)^ := v;
  end;
end;

function GetMethodAddr(cls: PClassRTTI; const name: string): Pointer;
var
  curr: PClassRTTI;
  meths: PMethInfo;
  i: Integer;
begin
  GetMethodAddr := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
      begin
        if meths[i].NamePtr^ = name then
        begin
          GetMethodAddr := meths[i].Code;
          Exit;
        end;
      end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

end.
