unit lfm;

{ Phase 5: LFM support, in-memory path.

  We have no runtime file I/O yet, so there is no standalone text->binary
  toolchain pass. Instead the `.lfm` *text* is embedded with the R directive
  (Phase 4) and converted to our TPF0 binary form (Phase 3) in memory at
  runtime by TLfmReader, then streamed into a component tree by TReader.

  Flow: TMyForm.Create -> InitInheritedComponent(Self, 'TMyForm')
        -> FindResource('TMyForm')           (the embedded .lfm text)
        -> TLfmReader.Convert(text -> TPF0 bytes)
        -> TReader.ReadRootComponent(Self).

  LFM text grammar handled (subset):
    object Name: ClassName
      PropName = Value
      object ChildName: ChildClass ... end
    end
  Values: integers, 'strings' (with '' escape), True/False, bare identifiers
  (enum members / event handler names), and [a, b] sets.

  Dialect notes: methods assign Result; pointer-typed class fields are copied to
  a local before indexing; no `shl`; byte work uses Integer ordinals, not
  single-char string literals. }

interface

uses typinfo, streams, classes_lite, resources;

type
  TLfmReader = class
  private
    FSrc:    PUInt8;
    FSrcLen: Integer;
    FSp:     Integer;
    FOut:    PUInt8;
    FOutN:   Integer;
    FTok:    array[0..4095] of Integer;   { current token bytes (holds longest string/ident) }
    FTokLen: Integer;
    FName:   array[0..255] of Integer;    { stashed component name }
    FNameLen: Integer;
    function  CurCh: Integer;             { byte at FSp, or -1 at eos }
    procedure Adv;
    procedure SkipWs;
    procedure EmitB(b: Integer);
    procedure EmitTok;                    { length-prefixed (shortstr) from FTok }
    procedure EmitTokString;              { vaString or vaLString from FTokLen }
    procedure EmitInt(v: Int64);
    procedure ReadIdent;                  { fill FTok with identifier bytes }
    procedure ReadQuoted;                 { fill FTok with string content }
    function  TokIs(const kw: string): Boolean;  { case-insensitive }
    procedure Expect(ch: Integer);
    procedure ParseValue;
    procedure ParseObject;                { precond: 'object' keyword consumed }
  public
    procedure Convert(srcData: Pointer; srcLen: Integer; outBuf: Pointer);
    function  OutLen: Integer;
  end;

procedure InitInheritedComponent(comp: TComponent; const className: string);

implementation

function TLfmReader.CurCh: Integer;
var p: PUInt8;
begin
  if FSp >= FSrcLen then
    Result := -1
  else
  begin
    p := FSrc;            { copy field to local before indexing }
    Result := p[FSp];
  end;
end;

procedure TLfmReader.Adv;
begin
  FSp := FSp + 1;
end;

procedure TLfmReader.SkipWs;
var c: Integer;
begin
  while True do
  begin
    c := CurCh;
    if (c = 32) or (c = 9) or (c = 13) or (c = 10) then Adv
    else Exit;
  end;
end;

procedure TLfmReader.EmitB(b: Integer);
var p: PUInt8;
begin
  p := FOut;
  p[FOutN] := Byte(b);
  FOutN := FOutN + 1;
end;

procedure TLfmReader.EmitTok;
var i: Integer;
begin
  EmitB(FTokLen);
  for i := 0 to FTokLen - 1 do EmitB(FTok[i]);
end;

procedure TLfmReader.EmitTokString;
var i: Integer;
begin
  if FTokLen <= 255 then
  begin
    EmitB(vaString);
    EmitTok;
  end
  else
  begin
    EmitB(vaLString);
    EmitB(FTokLen and 255);
    EmitB((FTokLen div 256) and 255);
    EmitB((FTokLen div 65536) and 255);
    EmitB((FTokLen div 16777216) and 255);
    for i := 0 to FTokLen - 1 do EmitB(FTok[i]);
  end;
end;

{ Choose the smallest signed value-type that fits. int64 path assumes a
  non-negative magnitude (no logical shift in the dialect); LFM ordinals that
  big do not occur in practice. }
procedure TLfmReader.EmitInt(v: Int64);
var w: Int64; i: Integer;
begin
  if (v >= -128) and (v <= 127) then
  begin
    EmitB(vaInt8);
    EmitB(Integer(v) and 255);
  end
  else if (v >= -32768) and (v <= 32767) then
  begin
    EmitB(vaInt16);
    w := v and 65535;
    EmitB(Integer(w) and 255);
    EmitB((Integer(w) div 256) and 255);
  end
  else if (v >= -2147483648) and (v <= 2147483647) then
  begin
    EmitB(vaInt32);
    w := v and $FFFFFFFF;
    EmitB(Integer(w and 255));
    EmitB(Integer((w div 256) and 255));
    EmitB(Integer((w div 65536) and 255));
    EmitB(Integer((w div 16777216) and 255));
  end
  else
  begin
    EmitB(vaInt64);
    w := v;
    for i := 0 to 7 do
    begin
      EmitB(Integer(w and 255));
      w := w div 256;
    end;
  end;
end;

procedure TLfmReader.ReadIdent;
var c: Integer;
begin
  FTokLen := 0;
  while True do
  begin
    c := CurCh;
    if ((c >= 65) and (c <= 90)) or ((c >= 97) and (c <= 122)) or
       ((c >= 48) and (c <= 57)) or (c = 95) or (c = 46) then
    begin
      FTok[FTokLen] := c;
      FTokLen := FTokLen + 1;
      Adv;
    end
    else
      Exit;
  end;
end;

procedure TLfmReader.ReadQuoted;
var c: Integer;
begin
  FTokLen := 0;
  Adv;                          { skip opening quote }
  while True do
  begin
    c := CurCh;
    if c = -1 then Exit;
    if c = 39 then              { quote }
    begin
      Adv;
      if CurCh = 39 then        { '' -> literal quote }
      begin
        FTok[FTokLen] := 39;
        FTokLen := FTokLen + 1;
        Adv;
      end
      else
        Exit;                   { end of string }
    end
    else
    begin
      FTok[FTokLen] := c;
      FTokLen := FTokLen + 1;
      Adv;
    end;
  end;
end;

function TLfmReader.TokIs(const kw: string): Boolean;
var i, a, b: Integer;
begin
  Result := False;
  if FTokLen <> Length(kw) then Exit;
  for i := 1 to FTokLen do
  begin
    a := FTok[i - 1];
    b := Ord(kw[i]);
    if (a >= 65) and (a <= 90) then a := a + 32;
    if (b >= 65) and (b <= 90) then b := b + 32;
    if a <> b then Exit;
  end;
  Result := True;
end;

procedure TLfmReader.Expect(ch: Integer);
begin
  SkipWs;
  if CurCh = ch then
    Adv
  else
  begin
    writeln('lfm: parse error, expected char code ', ch);
    Halt(1);
  end;
end;

procedure TLfmReader.ParseValue;
var c: Integer; v: Int64; neg, done: Boolean;
begin
  SkipWs;
  c := CurCh;
  if c = 39 then                          { quoted string }
  begin
    ReadQuoted;
    EmitTokString;
  end
  else if c = 91 then                     { '[' set }
  begin
    Adv;
    EmitB(vaSet);
    SkipWs;
    while CurCh <> 93 do                  { until ']' }
    begin
      SkipWs;
      ReadIdent;
      EmitTok;                            { member name }
      SkipWs;
      if CurCh = 44 then Adv;             { ',' }
      SkipWs;
    end;
    Adv;                                  { skip ']' }
    EmitB(0);                             { set terminator (empty shortstr) }
  end
  else if (c = 45) or ((c >= 48) and (c <= 57)) then  { number ('-' or digit) }
  begin
    neg := False;
    if c = 45 then begin neg := True; Adv; end;
    v := 0;
    done := False;
    while not done do
    begin
      c := CurCh;
      if (c >= 48) and (c <= 57) then
      begin
        v := v * 10 + (c - 48);
        Adv;
      end
      else
        done := True;
    end;
    if neg then v := -v;
    EmitInt(v);
  end
  else                                    { identifier: True/False/enum/event }
  begin
    ReadIdent;
    if TokIs('true') then
      EmitB(vaTrue)
    else if TokIs('false') then
      EmitB(vaFalse)
    else
    begin
      EmitB(vaIdent);
      EmitTok;
    end;
  end;
end;

procedure TLfmReader.ParseObject;
var inProps: Boolean; i: Integer;
begin
  SkipWs; ReadIdent;            { component Name }
  FNameLen := FTokLen;
  for i := 0 to FTokLen - 1 do FName[i] := FTok[i];

  Expect(58);                   { ':' }
  SkipWs; ReadIdent;            { ClassName -> FTok }

  { component = className:shortstr, name:shortstr, proplist, childlist }
  EmitTok;                      { className }
  EmitB(FNameLen);              { name }
  for i := 0 to FNameLen - 1 do EmitB(FName[i]);

  inProps := True;
  while True do
  begin
    SkipWs;
    if CurCh = -1 then Exit;
    ReadIdent;
    if TokIs('end') then
    begin
      if inProps then EmitB(0); { close proplist }
      EmitB(0);                 { close childlist }
      Exit;
    end
    else if TokIs('object') then
    begin
      if inProps then
      begin
        EmitB(0);               { close proplist before first child }
        inProps := False;
      end;
      ParseObject;              { 'object' keyword already consumed }
    end
    else
    begin
      { FTok holds the property name }
      EmitTok;                  { propname shortstr }
      Expect(61);               { '=' }
      ParseValue;
    end;
  end;
end;

procedure TLfmReader.Convert(srcData: Pointer; srcLen: Integer; outBuf: Pointer);
begin
  FSrc := PUInt8(srcData);
  FSrcLen := srcLen;
  FSp := 0;
  FOut := PUInt8(outBuf);
  FOutN := 0;

  EmitB(84); EmitB(80); EmitB(70); EmitB(48);   { 'TPF0' }
  SkipWs; ReadIdent;            { consume root 'object' keyword }
  ParseObject;
end;

function TLfmReader.OutLen: Integer;
begin
  Result := FOutN;
end;

procedure InitInheritedComponent(comp: TComponent; const className: string);
var
  data:   Pointer;
  len:    Integer;
  cls:    PClassRTTI;
  outBuf: Pointer;
  conv:   TLfmReader;
  st:     TByteStream;
  rd:     TReader;
begin
  cls := GetClass(className);
  if cls = nil then
  begin
    writeln('lfm: no RTTI for ', className);
    Halt(1);
  end;
  if not FindResource(className, data, len) then
  begin
    writeln('lfm: no resource for ', className);
    Halt(1);
  end;

  outBuf := GetMem(len * 2 + 256);
  conv := TLfmReader.Create;
  conv.Convert(data, len, outBuf);

  st := TByteStream.Create;
  st.Init(outBuf, conv.OutLen);
  rd := TReader.Create;
  rd.Init(st);
  rd.ReadRootComponent(comp, cls);
end;

end.
