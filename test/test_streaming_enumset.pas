program test_streaming_enumset;

{ Phase 3 streaming fidelity: enum (vaIdent), set (vaSet), and long-string
  (vaLString) property values. Builds a binary form stream by hand and streams
  it into a live instance, then asserts the enum ordinal, the set bitmask, and
  the long string round-trip. No GUI. }

uses typinfo, streams, classes_lite;

type
  TColor  = (clRed, clGreen, clBlue);
  TColors = set of TColor;

  TWidget = class(TComponent)
  private
    FColor:   TColor;
    FColors:  TColors;
    FCaption: string;
  published
    property Color:   TColor   read FColor   write FColor;
    property Colors:  TColors  read FColors  write FColors;
    property Caption: string   read FCaption write FCaption;
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

procedure PutLStr(const s: string);
var i, v: Integer;
begin
  v := Length(s);
  PutB(v and 255);
  PutB((v div 256) and 255);
  PutB((v div 65536) and 255);
  PutB((v div 16777216) and 255);
  for i := 1 to Length(s) do
    PutB(Ord(s[i]));
end;

var
  st:      TByteStream;
  rd:      TReader;
  w:       TWidget;
  cls:     PClassRTTI;
  pColor:  PPropInfo;
  pColors: PPropInfo;
  pCap:    PPropInfo;

begin
  { ---- build the stream ---- }
  bufN := 0;
  PutB(84); PutB(80); PutB(70); PutB(48);          { 'TPF0' }
  PutStr('TWidget');                                { root class }
  PutStr('W1');                                     { root name }
    PutStr('Color');   PutB(7);  PutStr('clGreen'); { vaIdent enum -> ord 1 }
    PutStr('Colors');  PutB(11);                    { vaSet }
      PutStr('clRed'); PutStr('clBlue'); PutStr(''); { members, '' terminator }
    PutStr('Caption'); PutB(12); PutLStr('Hello, long world!'); { vaLString }
    PutB(0);                                        { end root props }
    PutB(0);                                        { end root children }

  { ---- stream into an instance ---- }
  cls := GetClass('TWidget');
  if cls = nil then begin writeln('FAIL: no TWidget rtti'); Halt(1); end;

  w := TWidget.Create(nil);   { TComponent.Create now takes an owner (FPC-shaped) }
  st := TByteStream.Create;
  st.Init(@buf[0], bufN);
  rd := TReader.Create;
  rd.Init(st);
  rd.ReadRootComponent(w, cls);

  { ---- assert ---- }
  pColor  := GetPropInfo(cls, 'Color');
  pColors := GetPropInfo(cls, 'Colors');
  pCap    := GetPropInfo(cls, 'Caption');

  writeln('Color=',   GetOrdProp(Pointer(w), pColor));   { expect 1 }
  writeln('Colors=',  GetOrdProp(Pointer(w), pColors));  { clRed|clBlue = 1+4 = 5 }
  writeln('Caption=', GetStrProp(Pointer(w), pCap));     { Hello, long world! }
end.
