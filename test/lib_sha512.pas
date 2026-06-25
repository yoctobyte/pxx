program lib_sha512;
{ SHA-512 (FIPS 180-4) known-answer tests. }
uses sha512;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function ToHex(const r: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(r) do
  begin b := Ord(r[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

begin
  SayBool('sha512-empty', ToHex(Sha512('')) =
    'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e');
  SayBool('sha512-abc', ToHex(Sha512('abc')) =
    'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
  SayBool('sha512-len', Length(Sha512('the quick brown fox')) = 64);
end.
