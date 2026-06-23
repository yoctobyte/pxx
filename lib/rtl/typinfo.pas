unit typinfo;

interface

type
  { RTTI metadata name strings are emitted into the static blob as frozen,
    word-length-prefixed strings (rtti_emit.inc points NamePtr at Strs[].Offset).
    Under the managed-string default `string` is a refcounted handle, so a name
    pointer must be a FROZEN string pointer to read the inline [len][chars] blob
    correctly — `^string` would misread the length word as a managed handle and
    crash. string[255] is the frozen (tyFixedString) word-prefix kind. }
  TRttiStr = string[255];
  PString = ^TRttiStr;
  { Managed-string pointer for live instance string FIELDS (Get/SetStrProp): a
    `string` property field holds a managed handle under the default model. }
  PAnsiStr = ^string;

  TMethod = record
    Code: Pointer;
    Data: Pointer;
  end;
  PMethod = ^TMethod;

  { The RTTI blob (rtti_emit.inc) is emitted with uniform 8-byte field slots on
    every target (pointers and Int64 counts alike). To keep these reader records
    byte-compatible on 32-bit targets, a 4-byte stub follows each Pointer field
    under {$ifdef CPU32} so the pointer occupies a full 8-byte slot (the low 4
    bytes hold the 32-bit address, the stub is the zeroed high half). This is
    plain conditional compilation — no compiler/dialect change. TMethod is left
    unpadded: it is a runtime method-pointer value (8 bytes = 2 ptrs on i386),
    not a blob record. }
  TMethInfo = record
    NamePtr: PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    Code:    Pointer;
    {$ifdef CPU32} _pad_code: LongInt; {$endif}
  end;
  PMethInfo = ^TMethInfo;

  TFieldInfo = record
    NamePtr: PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    Offset:  Int64;       { byte offset of the field within the instance }
  end;
  PFieldInfo = ^TFieldInfo;

  TClassRTTI = record
    NamePtr:      PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    ParentRTTI:   Pointer; { actually PClassRTTI }
    {$ifdef CPU32} _pad_parent: LongInt; {$endif}
    InstanceSize: Int64;
    VMTPtr:       Pointer;
    {$ifdef CPU32} _pad_vmt: LongInt; {$endif}
    PropCount:    Int64;
    PropsPtr:     Pointer; { actually PPropInfo }
    {$ifdef CPU32} _pad_props: LongInt; {$endif}
    MethCount:    Int64;
    MethsPtr:     PMethInfo;
    {$ifdef CPU32} _pad_meths: LongInt; {$endif}
    FieldCount:   Int64;
    FieldsPtr:    PFieldInfo;
    {$ifdef CPU32} _pad_fields: LongInt; {$endif}
  end;
  PClassRTTI = ^TClassRTTI;

  PPString = ^PString;   { indexable array of PString (enum value-name table) }

  { The enum value-name table is emitted in the blob with the same uniform
    8-byte slots as every other RTTI pointer (see rtti_emit.inc EmitEnumRTTI:
    `cnt * 8` reservation, `i * 8` fixups). Read it through an 8-byte-padded
    slot so the stride matches on 32-bit too — a plain `array of PString` would
    step the native 4-byte pointer size on i386 and read every other slot as the
    zeroed high half (nil). Mirrors the TClassRTTI/TPropInfo padding. }
  TEnumValSlot = record
    P: PString;
    {$ifdef CPU32} _pad: LongInt; {$endif}
  end;
  PEnumValArr = ^TEnumValSlot;

  { Enum type RTTI blob (see rtti_emit.inc EmitEnumRTTI):
      +0  NamePtr   -> enum type name
      +8  Count     : Int64
      +16 ValuesPtr -> array[Count] of PString (member names, by ordinal) }
  TEnumRTTI = record
    NamePtr:   PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    Count:     Int64;
    ValuesPtr: Pointer; { actually PStringArr }
    {$ifdef CPU32} _pad_values: LongInt; {$endif}
  end;
  PEnumRTTI = ^TEnumRTTI;

  TPropInfo = record
    NamePtr: PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    Kind:    Int64;      { 0=int, 1=string, 2=class, 3=enum, 4=set, 5=method }
    TypeRef: Pointer;    { pointer to EnumRTTI or ClassRTTI or nil }
    {$ifdef CPU32} _pad_typeref: LongInt; {$endif}
    GetKind: Int64;      { 0=field, 1=method }
    GetRef:  Int64;      { field offset or method code ptr }
    SetKind: Int64;      { 0=field, 1=method }
    SetRef:  Int64;      { field offset or method code ptr }
    OrdType: Int64;      { type kind hint (size/sign for ordinals) }
  end;
  PPropInfo = ^TPropInfo;

  TRTTIEntry = record
    NamePtr: PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    RTTIPtr: PClassRTTI;
    {$ifdef CPU32} _pad_rtti: LongInt; {$endif}
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
  PPointer = ^Pointer;

function GetClass(const name: string): PClassRTTI;
function GetClassName(cls: PClassRTTI): string;
function CreateInstance(cls: PClassRTTI): Pointer;
function GetPropInfo(cls: PClassRTTI; const name: string): PPropInfo;
function GetPropList(cls: PClassRTTI; list: PPropList): Integer;
function GetOrdProp(instance: Pointer; p: PPropInfo): Int64;
procedure SetOrdProp(instance: Pointer; p: PPropInfo; v: Int64);
function GetStrProp(instance: Pointer; p: PPropInfo): string;
procedure SetStrProp(instance: Pointer; p: PPropInfo; const v: string);
function GetMethodProp(instance: Pointer; p: PPropInfo): TMethod;
procedure SetMethodProp(instance: Pointer; p: PPropInfo; const v: TMethod);
function GetMethodAddr(cls: PClassRTTI; const name: string): Pointer;
function SetFieldByName(instance: Pointer; cls: PClassRTTI; const name: string; value: Pointer): Boolean;
function GetEnumValue(et: PEnumRTTI; const name: string): Integer;
procedure SetSetProp(instance: Pointer; p: PPropInfo; ordinal: Integer);

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

function GetClassName(cls: PClassRTTI): string;
var ps: PString;
begin
  GetClassName := '';
  if cls = nil then Exit;
  ps := cls^.NamePtr;          { copy ptr field to local before deref }
  GetClassName := ps^;
end;

function CreateInstance(cls: PClassRTTI): Pointer;
var
  obj: Pointer;
begin
  CreateInstance := nil;
  if cls = nil then Exit;
  { Bump-allocated heap is kernel-zeroed, so all fields start cleared
    (string fields = empty). Mirror normal .Create: VMT pointer at offset 0. }
  obj := GetMem(Integer(cls^.InstanceSize));
  PPointer(obj)^ := cls^.VMTPtr;
  CreateInstance := obj;
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

type
  { setter method ABI: Self in the first slot (rdi), value in the second (rsi) —
    same convention the GTK trampolines call methods with. }
  TOrdSetter = procedure(Self: Pointer; v: Integer);
  TStrSetter = procedure(Self: Pointer; const v: string);

procedure SetOrdProp(instance: Pointer; p: PPropInfo; v: Int64);
var
  addr: Pointer;
  sz, tk: Integer;
  setter: TOrdSetter;
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
  end
  else
  begin
    { SetKind=1: SetRef is the setter method's code pointer. Invoke it so the
      property's side effects run (e.g. TControl.SetLeft updating the widget). }
    setter := TOrdSetter(Pointer(p^.SetRef));
    setter(instance, Integer(v));
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
    GetStrProp := PAnsiStr(addr)^;
  end;
end;

procedure SetStrProp(instance: Pointer; p: PPropInfo; const v: string);
var
  addr: Pointer;
  setter: TStrSetter;
begin
  if p^.SetKind = 0 then
  begin
    addr := @PUInt8(instance)[p^.SetRef];
    PAnsiStr(addr)^ := v;
  end
  else
  begin
    { SetKind=1: SetRef is the setter method's code pointer (e.g. SetCaption). }
    setter := TStrSetter(Pointer(p^.SetRef));
    setter(instance, v);
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
    { Copy the two pointers explicitly: a whole-record assignment through a
      casted-pointer deref currently moves only 8 bytes (drops Data). }
    m.Code := PMethod(addr)^.Code;
    m.Data := PMethod(addr)^.Data;
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
    { Store the two pointers explicitly: a whole-record assignment through a
      casted-pointer deref currently moves only 8 bytes (drops Data). }
    PMethod(addr)^.Code := v.Code;
    PMethod(addr)^.Data := v.Data;
  end;
end;

{ Map an enum member name to its ordinal via the enum RTTI. -1 if not found. }
function GetEnumValue(et: PEnumRTTI; const name: string): Integer;
var
  arr: PEnumValArr;
  sp: PString;
  i: Integer;
begin
  GetEnumValue := -1;
  if et = nil then Exit;
  arr := PEnumValArr(et^.ValuesPtr);
  if arr = nil then Exit;
  for i := 0 to Integer(et^.Count) - 1 do
  begin
    { copy the element pointer to a local before deref: inline index-then-deref
      (arr[i]^) of a pointer-array miscompiles in this dialect. The 8-byte-padded
      slot keeps the array stride uniform across targets (see PEnumValArr). }
    sp := arr[i].P;
    if sp^ = name then
    begin
      GetEnumValue := i;
      Exit;
    end;
  end;
end;

{ Set one member bit in a field-backed set property. Sets are 32-byte little-
  endian bitsets: member n lives at byte (n div 8), bit (n mod 8). No `shl` in
  this dialect, so build the mask by doubling. }
procedure SetSetProp(instance: Pointer; p: PPropInfo; ordinal: Integer);
var
  addr: PUInt8;
  byteIdx, bitIdx, mask, k: Integer;
begin
  if p^.SetKind = 0 then
  begin
    if (ordinal < 0) or (ordinal > 255) then Exit;
    addr := @PUInt8(instance)[p^.SetRef];
    byteIdx := ordinal div 8;
    bitIdx := ordinal - byteIdx * 8;
    mask := 1;
    for k := 1 to bitIdx do mask := mask * 2;
    addr[byteIdx] := Byte(Integer(addr[byteIdx]) or mask);
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

{ Store a pointer (a child component) into the published field named `name` of
  `instance`, walking the class hierarchy. Returns False if no such field. Used
  by the streamer to bind a named child into e.g. TForm1.Button1. }
function SetFieldByName(instance: Pointer; cls: PClassRTTI; const name: string; value: Pointer): Boolean;
var
  curr: PClassRTTI;
  fields: PFieldInfo;
  ps: PString;
  addr: Pointer;
  i: Integer;
begin
  SetFieldByName := False;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.FieldCount > 0 then
    begin
      fields := curr^.FieldsPtr;
      for i := 0 to Integer(curr^.FieldCount) - 1 do
      begin
        ps := fields[i].NamePtr;
        if ps^ = name then
        begin
          addr := @PUInt8(instance)[fields[i].Offset];
          PPointer(addr)^ := value;
          SetFieldByName := True;
          Exit;
        end;
      end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

end.
