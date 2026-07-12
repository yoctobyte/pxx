program test_ecdsa_sign;
{ ECDSA-P256 sign/keygen round-trip: a freshly generated key signs a message,
  the existing verifier accepts it, and rejects a tampered message/signature and
  a wrong key. Proves the new EcdsaP256Sign/PubFromPriv/GenKey against the
  independent EcdsaP256Verify path. }
uses sysutils, ecdsa_p256;

var
  priv, pub, priv2, pub2, sig, msg, bad: AnsiString;
  okGen, okVerify, rejMsg, rejSig, rejKey: Integer;

function Tamper(const s: AnsiString): AnsiString;
begin Tamper := s; if Length(Tamper) > 0 then Tamper[1] := Chr((Ord(Tamper[1]) + 1) and 255); end;

begin
  msg := 'pastella realm membership certificate v1';

  okGen := 0; okVerify := 0; rejMsg := 0; rejSig := 0; rejKey := 0;

  if EcdsaP256GenKey(priv, pub) and (Length(priv) = 32) and (Length(pub) = 64) then okGen := 1;

  sig := EcdsaP256Sign(priv, msg);
  if (Length(sig) = 64) and EcdsaP256Verify(pub, msg, sig) then okVerify := 1;

  if not EcdsaP256Verify(pub, msg + '!', sig) then rejMsg := 1;   { wrong message }
  if not EcdsaP256Verify(pub, msg, Tamper(sig)) then rejSig := 1; { tampered sig }

  EcdsaP256GenKey(priv2, pub2);
  if not EcdsaP256Verify(pub2, msg, sig) then rejKey := 1;        { wrong key }

  WriteLn('keygen=', okGen, ' sign+verify=', okVerify,
          ' reject: msg=', rejMsg, ' sig=', rejSig, ' key=', rejKey);
  if (okGen=1) and (okVerify=1) and (rejMsg=1) and (rejSig=1) and (rejKey=1) then
    WriteLn('ECDSA SIGN OK')
  else
    WriteLn('FAIL');
end.
