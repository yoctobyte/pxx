program lib_aead_key_and_iv_lengths;
{ AES-GCM at every key length and at IVs other than 12 bytes, ChaCha20-Poly1305,
  and the lengths both must REFUSE. The .expected is Python's cryptography
  package (test/lib_aead_key_and_iv_lengths.py), refusals included.
  Until 2026-09-29 a 32-byte AES key silently gave AES-128, an 8-byte IV gave
  output that was not GCM, and a 16-byte ChaCha key was read past its end. }
uses sysutils, aesgcm, chacha20poly1305;

function ToHex(const raw: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(raw) do
  begin b := Ord(raw[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

function Seq(n, mul, add: Integer): AnsiString;
var i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i + 1] := Chr((i * mul + add) and 255);
end;

function Key(n: Integer): AnsiString;
begin Result := Seq(n, 37, n); end;

function Iv(n: Integer): AnsiString;
begin Result := Seq(n, 11, 3 + n); end;

function IntS(n: Integer): AnsiString;
begin Str(n, Result); end;

var
  pt, aad, sealed, opened, bad, blk: AnsiString;
  kns, ivns: array[0..3] of Integer;
  badKeys: array[0..5] of Integer;
  ki, vi, n: Integer;
  seals, opens, raws: Boolean;

procedure AesRefused(const label_, k, v: AnsiString);
begin
  seals := False; opens := False;
  try AesGcmSeal(k, v, aad, pt); except on E: EAesGcm do seals := True; end;
  try AesGcmOpen(k, v, aad, Seq(40, 1, 0), opened); except on E: EAesGcm do opens := True; end;
  if seals and opens then writeln('refused ', label_)
  else writeln('ACCEPTED ', label_, ' seal-refused=', seals, ' open-refused=', opens);
end;

procedure ChaChaRefused(const label_, k, v: AnsiString);
begin
  seals := False; opens := False; raws := False;
  try Chacha20Poly1305Seal(k, v, aad, pt); except on E: EChaCha20Poly1305 do seals := True; end;
  try Chacha20Poly1305Open(k, v, aad, Seq(40, 1, 0), opened); except on E: EChaCha20Poly1305 do opens := True; end;
  try ChaCha20(k, 1, v, pt); except on E: EChaCha20Poly1305 do raws := True; end;
  if seals and opens and raws then writeln('refused ', label_)
  else writeln('ACCEPTED ', label_, ' seal-refused=', seals, ' open-refused=', opens,
               ' chacha20-refused=', raws);
end;

begin
  pt := Seq(37, 5, 1);
  aad := Seq(20, 3, 2);
  kns[0] := 16; kns[1] := 24; kns[2] := 32;
  ivns[0] := 12; ivns[1] := 8; ivns[2] := 16; ivns[3] := 60;

  blk := Seq(16, 17, 0);   { 00 11 22 .. ff }
  for ki := 0 to 2 do
    writeln('aes', kns[ki] * 8, '-block ', ToHex(AesEncryptBlock(Seq(kns[ki], 1, 0), blk)));

  for ki := 0 to 2 do
    for vi := 0 to 3 do
    begin
      sealed := AesGcmSeal(Key(kns[ki]), Iv(ivns[vi]), aad, pt);
      writeln('seal aes', kns[ki] * 8, '-gcm-iv', ivns[vi], ' ', ToHex(sealed));
      if AesGcmOpen(Key(kns[ki]), Iv(ivns[vi]), aad, sealed, opened) then
        writeln('open aes', kns[ki] * 8, '-gcm-iv', ivns[vi], ' ', ToHex(opened))
      else
        writeln('open aes', kns[ki] * 8, '-gcm-iv', ivns[vi], ' False');
      bad := sealed;
      bad[1] := Chr(Ord(bad[1]) xor 1);
      if AesGcmOpen(Key(kns[ki]), Iv(ivns[vi]), aad, bad, opened) then
        writeln('open aes', kns[ki] * 8, '-gcm-iv', ivns[vi], ' tampered opened')
      else
        writeln('open aes', kns[ki] * 8, '-gcm-iv', ivns[vi], ' tampered False');
    end;

  badKeys[0] := 0; badKeys[1] := 15; badKeys[2] := 17;
  badKeys[3] := 31; badKeys[4] := 33; badKeys[5] := 64;
  for ki := 0 to 5 do
    AesRefused('aes-gcm-key' + IntS(badKeys[ki]), Key(badKeys[ki]), Iv(12));
  AesRefused('aes-gcm-iv0', Key(32), '');

  sealed := Chacha20Poly1305Seal(Key(32), Iv(12), aad, pt);
  writeln('seal chacha20poly1305 ', ToHex(sealed));
  if Chacha20Poly1305Open(Key(32), Iv(12), aad, sealed, opened) then
    writeln('open chacha20poly1305 ', ToHex(opened))
  else
    writeln('open chacha20poly1305 False');
  badKeys[0] := 0; badKeys[1] := 16; badKeys[2] := 31; badKeys[3] := 33;
  for ki := 0 to 3 do
    ChaChaRefused('chacha20poly1305-key' + IntS(badKeys[ki]), Key(badKeys[ki]), Iv(12));
  ChaChaRefused('chacha20poly1305-nonce8', Key(32), Iv(8));
  ChaChaRefused('chacha20poly1305-nonce16', Key(32), Iv(16));

  { Poly1305 on its own: no Python counterpart line, so it only speaks up
    when it fails to refuse. }
  n := 0;
  try Poly1305(Key(16), pt); except on E: EChaCha20Poly1305 do n := 1; end;
  if n = 0 then writeln('ACCEPTED poly1305-key16');
end.
