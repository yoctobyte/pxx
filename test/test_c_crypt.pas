program test_c_crypt;
uses crypt, sysutils;

procedure Fail(const msg: string);
begin
  writeln('FAIL: ', msg);
  halt(1);
end;

function PCharEquals(p1, p2: PChar): Boolean;
var
  i: Integer;
begin
  i := 0;
  while (p1[i] <> #0) and (p2[i] <> #0) and (p1[i] = p2[i]) do
    Inc(i);
  Result := (p1[i] = #0) and (p2[i] = #0);
end;

function PCharHasPrefix(p: PChar; const prefix: string): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 1 to Length(prefix) do
  begin
    if p[i - 1] <> prefix[i] then
    begin
      Result := False;
      Break;
    end;
  end;
end;

var
  phrase, setting, hash1, hash2: PChar;
  data: crypt_data;
begin
  phrase := PChar('supersecretpassword');
  setting := PChar('$6$saltsalt$');

  // 1. Test standard crypt (non-thread-safe, static buffer)
  hash1 := crypt(phrase, setting);
  if hash1 = nil then
    Fail('crypt returned nil');
  if hash1[0] = '*' then
    Fail('crypt returned error: ' + hash1);

  writeln('crypt hash: ', hash1);
  if not PCharHasPrefix(hash1, '$6$saltsalt$') then
    Fail('Hash does not match expected prefix: $6$saltsalt$');

  // 2. Test thread-safe crypt_r
  FillChar(data, sizeof(data), 0);
  hash2 := crypt_r(phrase, setting, @data);
  if hash2 = nil then
    Fail('crypt_r returned nil');

  writeln('crypt_r hash: ', hash2);

  // The returned pointer should point to the output buffer inside our data record
  if hash2 <> @data.output[0] then
    Fail('crypt_r returned pointer does not point to data.output');

  // Verify both hashes are identical
  if not PCharEquals(hash1, hash2) then
    Fail('crypt and crypt_r hashes are not identical');

  writeln('All crypt tests passed successfully!');
end.
