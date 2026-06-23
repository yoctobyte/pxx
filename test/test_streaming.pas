program test_streaming;

{ Phase 3 streaming runtime test. Builds a binary form stream (our TPF0 subset)
  describing a root component with int/string props and an event, plus one
  child with an int prop, then streams it into live instances via TReader and
  asserts the values + the bound event address. No GUI. }

uses typinfo, streams, classes_lite;

type
  TRoot = class(TComponent)
  private
    FCount: Integer;
    FTitle: string;
    FOnGo:  TMethod;
  public
    procedure Handler;
  published
    property Count: Integer read FCount write FCount;
    property Title: string read FTitle write FTitle;
    property OnGo:  TMethod read FOnGo write FOnGo;
  end;

  TChildC = class(TComponent)
  private
    FValue: Integer;
  published
    property Value: Integer read FValue write FValue;
  end;

procedure TRoot.Handler;
begin
  writeln('handler ran');
end;

var
  buf:  array[0..255] of Byte;
  bufN: Integer;

procedure PutB(b: Integer);
begin
  buf[bufN] := b;
  bufN := bufN + 1;
end;

procedure PutStr(const s: string);
var i: Integer;
begin
  PutB(Length(s));
  for i := 1 to Length(s) do
    PutB(Ord(s[i]));
end;

procedure PutInt32(v: Integer);
begin
  PutB(v and 255);
  PutB((v div 256) and 255);
  PutB((v div 65536) and 255);
  PutB((v div 16777216) and 255);
end;

var
  st:       TByteStream;
  rd:       TReader;
  root:     TRoot;
  rootCls:  PClassRTTI;
  childCls: PClassRTTI;
  kid:      TComponent;
  kidV:     PPropInfo;
  pOnGo:    PPropInfo;
  expectCode: Pointer;
  m:        TMethod;

begin
  { ---- build the stream ---- }
  bufN := 0;
  PutB(84); PutB(80); PutB(70); PutB(48);    { 'TPF0' }
  PutStr('TRoot');                            { root class }
  PutStr('Root1');                            { root name }
    PutStr('Count'); PutB(4);  PutInt32(42);  { vaInt32 }
    PutStr('Title'); PutB(6);  PutStr('Hi');  { vaString }
    PutStr('OnGo');  PutB(7);  PutStr('Handler'); { vaIdent -> event }
    PutB(0);                                  { end root props }
    PutStr('TChildC');                        { child class }
      PutStr('Kid1');                         { child name }
      PutStr('Value'); PutB(2); PutB(7);      { vaInt8 = 7 }
      PutB(0);                                { end child props }
      PutB(0);                                { end child children }
    PutB(0);                                  { end root children }

  { ---- stream it into instances ---- }
  rootCls := GetClass('TRoot');
  if rootCls = nil then begin writeln('FAIL: no TRoot rtti'); Halt(1); end;

  root := TRoot.Create(nil);   { TComponent.Create now takes an owner (FPC-shaped) }
  st := TByteStream.Create;
  st.Init(@buf[0], bufN);
  rd := TReader.Create;
  rd.Init(st);
  rd.ReadRootComponent(root, rootCls);

  { ---- assert root ---- }
  writeln('root.Name=', root.Name);
  writeln('root.Count=', root.Count);
  writeln('root.Title=', root.Title);

  expectCode := GetMethodAddr(rootCls, 'Handler');
  pOnGo := GetPropInfo(rootCls, 'OnGo');
  m := GetMethodProp(Pointer(root), pOnGo);
  if m.Code = expectCode then
    writeln('OnGo bound: yes')
  else
    writeln('OnGo bound: no');

  { ---- assert child ---- }
  writeln('childCount=', root.ChildCount);
  kid := root.FindChild('Kid1');
  if kid = nil then begin writeln('FAIL: no child Kid1'); Halt(1); end;
  writeln('kid.Name=', kid.Name);
  childCls := GetClass('TChildC');
  kidV := GetPropInfo(childCls, 'Value');
  writeln('kid.Value=', GetOrdProp(Pointer(kid), kidV));
end.
