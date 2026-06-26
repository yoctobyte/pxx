program lib_base64;
{ RFC 4648 Base64 round-trip + known vectors + padding + invalid-input. }
uses hashing, base64;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var data: TByteArray; ok: Boolean; i: Integer; s: AnsiString;
begin
  { RFC 4648 test vectors. }
  SayBool('enc-empty',  Base64EncodeStr('') = '');
  SayBool('enc-f',      Base64EncodeStr('f') = 'Zg==');
  SayBool('enc-fo',     Base64EncodeStr('fo') = 'Zm8=');
  SayBool('enc-foo',    Base64EncodeStr('foo') = 'Zm9v');
  SayBool('enc-foob',   Base64EncodeStr('foob') = 'Zm9vYg==');
  SayBool('enc-fooba',  Base64EncodeStr('fooba') = 'Zm9vYmE=');
  SayBool('enc-foobar', Base64EncodeStr('foobar') = 'Zm9vYmFy');

  { Decode the same vectors. }
  SayBool('dec-f',      Base64DecodeStr('Zg==') = 'f');
  SayBool('dec-fo',     Base64DecodeStr('Zm8=') = 'fo');
  SayBool('dec-foobar', Base64DecodeStr('Zm9vYmFy') = 'foobar');

  { Basic-auth style credential. }
  SayBool('enc-creds',  Base64EncodeStr('user:pass') = 'dXNlcjpwYXNz');

  { Whitespace tolerated on decode (line-wrapped MIME). }
  SayBool('dec-ws',     Base64DecodeStr('Zm9v'#13#10'YmFy') = 'foobar');

  { Round-trip over all byte values. }
  SetLength(data, 256);
  for i := 0 to 255 do data[i] := Byte(i);
  s := Base64Encode(data);
  ok := Base64Decode(s, data) and (Length(data) = 256);
  if ok then
    for i := 0 to 255 do
      if data[i] <> Byte(i) then ok := False;
  SayBool('roundtrip-256', ok);

  { Invalid character rejected. }
  SayBool('dec-bad',    not Base64Decode('Zm9v*bad', data));
end.
