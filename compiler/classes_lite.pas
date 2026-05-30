unit classes_lite;

{ Phase 3 streaming runtime: a TComponent-lite base and a TReader that
  instantiates and configures a component tree from a binary form stream,
  using the published RTTI (typinfo) and a byte stream (streams).

  Binary form (our minimal TPF0 subset — NOT byte-identical to Delphi):
    stream    = 'T','P','F','0', component
    component = className:shortstr, name:shortstr, proplist, childlist
    proplist  = zero or more (propname:shortstr, valuetype:byte, value), then 0x00
    childlist = zero or more (component), then 0x00
  A className/propname length byte of 0 terminates the enclosing list
  (real class/prop names are never empty), so no separate flag bytes.

  Dialect notes: methods assign Result (never the method name); pointer-typed
  class fields are not indexed directly; strings come from the stream, never
  single-char literals. }

interface

uses typinfo, streams;

const
  { TPF0 value-type bytes (Delphi filer subset we support) }
  vaInt8   = 2;
  vaInt16  = 3;
  vaInt32  = 4;
  vaString = 6;
  vaIdent  = 7;
  vaFalse  = 8;
  vaTrue   = 9;
  vaInt64  = 19;

type
  TComponent = class
  private
    FName: string;
    FChildren: array[0..63] of TComponent;
    FChildCount: Integer;
  public
    procedure AddChild(c: TComponent);
    function ChildCount: Integer;
    function Child(i: Integer): TComponent;
    function FindChild(const nm: string): TComponent;
  published
    property Name: string read FName write FName;
  end;

  TReader = class
  private
    FStream: TByteStream;
    procedure SetCompName(inst: Pointer; cls: PClassRTTI; const nm: string);
    procedure ReadProps(inst: Pointer; cls: PClassRTTI; rootInst: Pointer; rootCls: PClassRTTI);
    procedure ReadBody(comp: TComponent; cls: PClassRTTI; rootInst: Pointer; rootCls: PClassRTTI);
    procedure ReadChildren(parent: TComponent; rootInst: Pointer; rootCls: PClassRTTI);
  public
    procedure Init(stream: TByteStream);
    procedure ReadRootComponent(root: TComponent; rootCls: PClassRTTI);
  end;

implementation

{ ---------- TComponent ---------- }

procedure TComponent.AddChild(c: TComponent);
begin
  if FChildCount <= 63 then
  begin
    FChildren[FChildCount] := c;
    FChildCount := FChildCount + 1;
  end;
end;

function TComponent.ChildCount: Integer;
begin
  Result := FChildCount;
end;

function TComponent.Child(i: Integer): TComponent;
begin
  Result := FChildren[i];
end;

function TComponent.FindChild(const nm: string): TComponent;
var i: Integer; c: TComponent;
begin
  Result := nil;
  for i := 0 to FChildCount - 1 do
  begin
    c := FChildren[i];
    if c.Name = nm then
    begin
      Result := c;
      Exit;
    end;
  end;
end;

{ ---------- TReader ---------- }

procedure TReader.Init(stream: TByteStream);
begin
  FStream := stream;
end;

procedure TReader.SetCompName(inst: Pointer; cls: PClassRTTI; const nm: string);
var p: PPropInfo;
begin
  p := GetPropInfo(cls, 'Name');
  if p <> nil then SetStrProp(inst, p, nm);
end;

procedure StreamFail(const msg: string);
begin
  writeln('streaming error: ', msg);
  Halt(1);
end;

procedure TReader.ReadProps(inst: Pointer; cls: PClassRTTI; rootInst: Pointer; rootCls: PClassRTTI);
var
  lenByte, vt: Integer;
  v: Int64;
  propName, sv, ident: string;
  p: PPropInfo;
  m: TMethod;
begin
  while True do
  begin
    lenByte := FStream.ReadByte;
    if lenByte = 0 then Exit;          { 0 length = end of property list }
    propName := FStream.ReadStrLen(lenByte);
    vt := FStream.ReadByte;
    p := GetPropInfo(cls, propName);
    { Always consume the value (even if the prop is unknown) to stay in sync. }
    if vt = vaInt8 then
    begin
      v := FStream.ReadInt8;
      if p <> nil then SetOrdProp(inst, p, v);
    end
    else if vt = vaInt16 then
    begin
      v := FStream.ReadInt16;
      if p <> nil then SetOrdProp(inst, p, v);
    end
    else if vt = vaInt32 then
    begin
      v := FStream.ReadInt32;
      if p <> nil then SetOrdProp(inst, p, v);
    end
    else if vt = vaInt64 then
    begin
      v := FStream.ReadInt64;
      if p <> nil then SetOrdProp(inst, p, v);
    end
    else if vt = vaTrue then
    begin
      if p <> nil then SetOrdProp(inst, p, 1);
    end
    else if vt = vaFalse then
    begin
      if p <> nil then SetOrdProp(inst, p, 0);
    end
    else if vt = vaString then
    begin
      sv := FStream.ReadShortStr;
      if p <> nil then SetStrProp(inst, p, sv);
    end
    else if vt = vaIdent then
    begin
      ident := FStream.ReadShortStr;
      if (p <> nil) and (p^.Kind = 5) then   { piMethod: an event }
      begin
        m.Code := GetMethodAddr(rootCls, ident);
        m.Data := rootInst;
        SetMethodProp(inst, p, m);
      end;
    end
    else
      StreamFail('unsupported value type');
  end;
end;

procedure TReader.ReadBody(comp: TComponent; cls: PClassRTTI; rootInst: Pointer; rootCls: PClassRTTI);
var nm: string;
begin
  nm := FStream.ReadShortStr;            { component Name }
  SetCompName(comp, cls, nm);
  ReadProps(comp, cls, rootInst, rootCls);
  ReadChildren(comp, rootInst, rootCls);
end;

procedure TReader.ReadChildren(parent: TComponent; rootInst: Pointer; rootCls: PClassRTTI);
var
  lenByte: Integer;
  className: string;
  childCls: PClassRTTI;
  childP: Pointer;
  child: TComponent;
begin
  while True do
  begin
    lenByte := FStream.ReadByte;
    if lenByte = 0 then Exit;            { 0 length = end of child list }
    className := FStream.ReadStrLen(lenByte);
    childCls := GetClass(className);
    if childCls = nil then StreamFail('unknown class');
    childP := CreateInstance(childCls);
    child := childP;
    ReadBody(child, childCls, rootInst, rootCls);
    parent.AddChild(child);
  end;
end;

procedure TReader.ReadRootComponent(root: TComponent; rootCls: PClassRTTI);
var className: string;
begin
  if FStream.ReadByte <> 84 then StreamFail('bad signature');  { 'T' }
  if FStream.ReadByte <> 80 then StreamFail('bad signature');  { 'P' }
  if FStream.ReadByte <> 70 then StreamFail('bad signature');  { 'F' }
  if FStream.ReadByte <> 48 then StreamFail('bad signature');  { '0' }
  className := FStream.ReadShortStr;     { root class name (informational) }
  ReadBody(root, rootCls, root, rootCls);
end;

end.
